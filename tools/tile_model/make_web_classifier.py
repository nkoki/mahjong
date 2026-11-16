"""Web 版のカメラ認識で使う分類モデル（web/models/tile_classifier_web.tflite）を作る。

アプリ版の分類モデル（assets/models/tile_classifier.tflite）は、1度に読む枚数が決まっていない形
（入力が [-1, 128, 96, 3]）になっている。ブラウザで .tflite を動かす LiteRT.js はこの形を読めないので、
枚数を 1 に決めた写しを作る。変えるのは形の情報だけで、重み（学習した中身）は同じ。

分類モデルを学習し直したら、リポジトリのいちばん上で次を実行して作り直す
（作り直さないと test/web_recognizer_test.dart が失敗する）。

  pip install ai-edge-litert numpy
  python tools/tile_model/make_web_classifier.py

作ったあと、同じ入力で元のモデルと答えが同じになることを確かめる。
"""

import sys
from pathlib import Path

import flatbuffers
import numpy as np
from ai_edge_litert import schema_py_generated as schema
from ai_edge_litert.interpreter import Interpreter

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets/models/tile_classifier.tflite"
OUT = ROOT / "web/models/tile_classifier_web.tflite"
SUM = ROOT / "web/models/tile_classifier_web.source.txt"


def fnv1a(data: bytes) -> int:
    """元のファイルが変わっていないかを確かめるための値（FNV-1a 32ビット。Dart のテストでも同じ計算をする）"""
    h = 0x811C9DC5
    for b in data:
        h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
    return h


def main():
    src = SRC.read_bytes()
    model = schema.ModelT.InitFromPackedBuf(src, 0)
    changed = 0
    for sub in model.subgraphs:
        for t in sub.tensors:
            sig = t.shapeSignature
            if sig is not None and len(sig) > 0 and sig[0] == -1:
                if any(d == -1 for d in list(sig)[1:]):
                    sys.exit(f"枚数以外も決まっていない入力があります: {t.name} {list(sig)}")
                sig = np.array(sig, dtype=np.int32)
                sig[0] = 1
                t.shapeSignature = sig
                changed += 1
    builder = flatbuffers.Builder(len(src) + 1024)
    builder.Finish(model.Pack(builder), b"TFL3")
    out = bytes(builder.Output())
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(out)
    SUM.write_text(f"{len(src)} {fnv1a(src):08x}\n")

    # 同じ入力で、元のモデルと答えが同じになることを確かめる
    def run(path, x):
        it = Interpreter(model_path=str(path), num_threads=1)
        it.allocate_tensors()
        i = it.get_input_details()[0]
        it.set_tensor(i["index"], x)
        it.invoke()
        return i["shape_signature"], it.get_tensor(it.get_output_details()[0]["index"])

    rng = np.random.default_rng(0)
    worst = 0.0
    for _ in range(5):
        x = (rng.random((1, 128, 96, 3), dtype=np.float32) * 255).astype(np.float32)
        (_, a), (sig, b) = run(SRC, x), run(OUT, x)
        worst = max(worst, float(np.abs(a - b).max()))
    if list(sig)[0] != 1 or worst > 1e-6:
        sys.exit(f"作ったモデルが元と合いません（形 {list(sig)}、答えの差 {worst}）")
    print(f"wrote {OUT.relative_to(ROOT)}（形を変えた所 {changed}、元との答えの差 {worst}、{len(out)} バイト）")


if __name__ == "__main__":
    main()
