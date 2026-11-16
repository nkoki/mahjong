// Web 版のカメラ認識で使うファイルを web/litert/ に作る。
//
//   cd tools/web_litert && npm ci && npm run build
//
// - tile_models.js: src/tile_models.js と LiteRT.js を1つにまとめたもの
// - litert_wasm_*.{js,wasm}: LiteRT.js の WebAssembly（ブラウザに合うほうの1組だけが読み込まれる）
// web/litert/ は Git には入れない（大きいので、ビルドのたびに npm から作る。版は package-lock.json で固定）。
import { build } from 'esbuild';
import { copyFileSync, mkdirSync, rmSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const out = join(here, '..', '..', 'web', 'litert');
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

await build({
  entryPoints: [join(here, 'src', 'tile_models.js')],
  bundle: true,
  format: 'esm',
  minify: true,
  legalComments: 'none',
  outfile: join(out, 'tile_models.js'),
});

// スレッド・JSPI を使う版は、GitHub Pages では使えない（特別な HTTP ヘッダーが必要）ので入れない
const wasmDir = join(here, 'node_modules', '@litertjs', 'core', 'wasm');
for (const name of ['litert_wasm_internal', 'litert_wasm_compat_internal']) {
  for (const ext of ['js', 'wasm']) copyFileSync(join(wasmDir, `${name}.${ext}`), join(out, `${name}.${ext}`));
}
copyFileSync(join(here, 'node_modules', '@litertjs', 'core', 'package.json'), join(out, 'litert-package.json'));
for (const f of ['tile_models.js', 'litert_wasm_internal.wasm', 'litert_wasm_compat_internal.wasm']) {
  console.log(f, statSync(join(out, f)).size);
}
