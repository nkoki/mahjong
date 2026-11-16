// Web 版のカメラ認識: 牌の認識モデル（.tflite）をブラウザの中で動かす。
//
// アプリ（Dart）から呼ぶ入口を globalThis.mahjongTileModels に置く。
// 写真やモデルの計算はすべてこの端末の中で行い、どこにも送らない。
// 実行は WebAssembly（CPU）で行う。GPU は端末ごとに結果が少し変わるので使わない。
import { loadLiteRt, loadAndCompile, Tensor } from '@litertjs/core';

let runtime; // LiteRT.js の読み込み（1回だけ）
const models = new Map();

/** LiteRT.js の WebAssembly を読み込む。[wasmDir] は .wasm のあるフォルダの URL */
async function init(wasmDir) {
  if (!runtime) {
    runtime = loadLiteRt(wasmDir).catch((e) => {
      runtime = undefined;
      throw e;
    });
  }
  await runtime;
}

/**
 * モデルを読み込み、入力の形（例: [1, 384, 384, 3]）を返す。
 * [source] は .tflite の中身（Uint8Array）か、ページからの相対の場所（文字列）
 */
async function loadModel(name, source) {
  if (!models.has(name)) {
    const model = typeof source === 'string' ? new URL(source, document.baseURI).href : source;
    models.set(name, await loadAndCompile(model, { accelerator: 'wasm' }));
  }
  // 枚数が決まっていないモデル（先頭が -1）は、1枚ずつ動かす
  return Array.from(models.get(name).getInputDetails()[0].shape, (d) => (d < 0 ? 1 : d));
}

/**
 * モデルを1回動かす。[input] は Float32Array、[shape] は入力の形。
 * 出力ごとに { shape, data } を、モデルの出力の順で返す。
 */
async function run(name, input, shape) {
  const model = models.get(name);
  if (!model) throw new Error(`model not loaded: ${name}`);
  const tensor = new Tensor(input, shape);
  let results;
  try {
    results = await model.run(tensor);
    return results.map((t) => ({
      shape: Array.from(t.shape),
      // 結果は WebAssembly のメモリの上にあるので、写しを返す
      data: new Float32Array(t.toTypedArray()),
    }));
  } finally {
    tensor.delete();
    if (results) for (const t of results) t.delete();
  }
}

globalThis.mahjongTileModels = { init, loadModel, run };
