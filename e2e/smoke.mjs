// Web 版を実際のブラウザで動かして、主な操作が通るかを確かめる（E2E テスト）。
//
// 使い方（リポジトリのいちばん上で）:
//   (cd tools/web_litert && npm ci && npm run build)   # カメラ認識（Web 版）で使う LiteRT.js を web/litert/ に作る
//   flutter build web --release --no-web-resources-cdn --base-href /mahjong/
//   mkdir -p /tmp/site && cp -r build/web /tmp/site/mahjong && (cd /tmp/site && python3 -m http.server 8765 &)
//   cd e2e && npm ci && npx playwright install chromium && node smoke.mjs http://localhost:8765/mahjong/
//
// Flutter の Web 版は画面を canvas に描くので、読み上げ用の情報（セマンティクス）を有効にしてから、
// ボタンなどを名前で探して操作する。
import { chromium } from 'playwright';

const url = process.argv[2] ?? 'http://localhost:8765/mahjong/';
const shotDir = process.argv[3];
// 枠つきの撮影の確認用に、ブラウザの偽のカメラに fixtures/guided_camera.mjpeg の映像を流す（許可の確認は出さない）
const fixture = (name) => new URL(`fixtures/${name}`, import.meta.url).pathname;
const browser = await chromium.launch({
  args: [
    '--use-fake-device-for-media-stream',
    '--use-fake-ui-for-media-stream',
    `--use-file-for-fake-video-capture=${fixture('guided_camera.mjpeg')}`,
  ],
});
const page = await browser.newPage({ viewport: { width: 400, height: 860 }, permissions: ['camera'] });
const external = new Set();
page.on('request', (r) => {
  const u = new URL(r.url());
  // blob: や data:（選んだ写真など、ブラウザの中だけのもの）は通信ではないので数えない
  if (!u.protocol.startsWith('http')) return;
  if (u.hostname !== new URL(url).hostname) external.add(u.hostname);
});
page.on('pageerror', (e) => { throw e; });

let step = 0;
async function shot(name) {
  if (shotDir) await page.screenshot({ path: `${shotDir}/${String(++step).padStart(2, '0')}-${name}.png` });
}

/** 名前の部品を探す。見つからなければ画面を下へ動かして探し直す */
async function find(role, name, { nth = 0, exact = true } = {}) {
  for (let i = 0; i < 25; i++) {
    const l = page.getByRole(role, { name, exact });
    if ((await l.count()) > nth) return l.nth(nth);
    await page.mouse.move(200, 430);
    await page.mouse.wheel(0, 300);
    await page.waitForTimeout(250);
  }
  throw new Error(`見つかりません: ${role} 「${name}」`);
}
async function tap(name, opts = {}) {
  await (await find(opts.role ?? 'button', name, opts)).click();
  await page.waitForTimeout(500);
}
async function expectText(text, tries = 20) {
  for (let i = 0; i < tries; i++) {
    const html = await page.content();
    if (html.includes(text)) return;
    await page.waitForTimeout(250);
  }
  throw new Error(`画面に「${text}」がありません`);
}

await page.goto(url);
await page.waitForSelector('flt-semantics-placeholder', { state: 'attached', timeout: 60000 });
await page.evaluate(() => document.querySelector('flt-semantics-placeholder').click());
await page.waitForTimeout(1000);
await shot('home');

// 新規対局（名前は空のまま → プレイヤー1〜4）
await tap('新規対局');
await tap('対局開始');
await expectText('東1局 0本場');
await shot('dashboard');

// 和了: 南家（プレイヤー2）が西家（プレイヤー3）から、翻・符で 3翻40符（5200点）
await tap('和了');
// 選択ボタン（ChoiceChip）は読み上げでは checkbox になる。和了者と放銃者の欄に同じ名前があるので、放銃者は2つ目
await tap('南 プレイヤー2', { role: 'checkbox' });
await tap('西 プレイヤー3', { role: 'checkbox', nth: 1 });
await tap('翻・符で入力');
await tap('3翻', { role: 'checkbox' });
await tap('40符', { role: 'checkbox' });
await expectText('子のロン 5200点');
await shot('win-input');
await tap('計算');
await expectText('3翻 40符');
await tap('この結果で確定');
await expectText('東2局 0本場');
await expectText('30,200');
await expectText('19,800');
await shot('after-win');

// カメラ認識（Web 版）: 写真を選ぶと、ブラウザの中で認識モデル（LiteRT.js）が動いて牌を読み取る。
// 写真は fixtures/hand.jpg（左から 白 6索 1萬 3筒 3索 3萬 1筒 白 9萬）
await tap('和了');
await tap('カメラで手牌を読み取る');
await expectText('初めて使うときだけ、認識モデル');
const chooser = page.waitForEvent('filechooser');
await tap('写真から選ぶ', { exact: false });
await (await chooser).setFiles(fixture('hand.jpg'));
await expectText('読み取った牌（9枚）', 240);
// 読み取った順（左から）に、牌の読み上げ用の名前が並ぶ
const read = await page.evaluate(() => {
  const labels = [...document.querySelectorAll('flt-semantics')]
    .map((e) => e.getAttribute('aria-label') ?? ([...e.children].some((c) => c.tagName.toLowerCase().startsWith('flt-semantics')) ? '' : e.textContent))
    .filter(Boolean);
  const a = labels.findIndex((t) => t.startsWith('読み取った牌'));
  const b = labels.findIndex((t, i) => i > a && t.startsWith('手牌（'));
  return labels.slice(a + 1, b).join(' ');
});
const wantRead = '白 6索 1萬 3筒 3索 3萬 1筒 白 9萬';
if (read !== wantRead) throw new Error(`カメラ認識の結果が違います: 「${read}」（正しくは「${wantRead}」）`);
await shot('camera-result');
await tap('手牌に入れる');
await expectText('読み取った牌を入れました');

// 枠つきの撮影（Web 版）: カメラの映像に4つのエリアを重ねた画面で撮り、エリアごとに読み取る。
// 偽のカメラの映像は、ドラ表示牌に2枚、鳴いた牌に 中のポン と 2-3-4筒のチー（離さずに並べる）、手牌に7枚、和了牌に 8筒
// 映像は画面いっぱいに広げて出す。確認用の映像（fixtures/make_guided_camera.py）は、画面が 幅 800 × 高さ 860 のときに
// 牌がエリアに入るように作ってあるので、撮影の間だけ画面の大きさを合わせる
await page.setViewportSize({ width: 800, height: 860 });
await page.waitForTimeout(500);
await tap('カメラで手牌を読み取る');
await tap('エリアに合わせて撮影する', { exact: false });
await expectText('ドラ表示牌（下の段に裏ドラ）', 80);
await page.waitForTimeout(1500); // 映像が出るのを待つ
await shot('guided-camera');
await tap('撮影');
await expectText('手牌（7/7枚）', 240);
const guided = await page.evaluate(() =>
  [...document.querySelectorAll('flt-semantics')]
    .map((e) => e.getAttribute('aria-label') ?? ([...e.children].some((c) => c.tagName.toLowerCase().startsWith('flt-semantics')) ? '' : e.textContent))
    .filter(Boolean)
    .join(' '));
const wantGuided = '手牌（7/7枚） 2萬 3萬 4萬 6筒 7筒 5索 5索 和了牌:  8筒 鳴き（2） チー 2筒 3筒 4筒 ポン 中 中 中 ドラ表示牌（2） 5索 4筒 裏ドラ表示牌（1） 6筒';
if (!guided.replace(/\s+/g, ' ').includes(wantGuided.replace(/\s+/g, ' '))) {
  throw new Error(`枠つきの撮影の結果が違います: 「${guided}」`);
}
await shot('guided-result');
await tap('手牌に入れる');
await page.setViewportSize({ width: 400, height: 860 });
await page.waitForTimeout(500);
// 鳴きが2組入ったので、手牌は 13 - 3×2 = 7枚になる
await expectText('手牌（7/7枚・タップで削除）');
await shot('guided-applied');
await tap('Back');

// 流局（全員ノーテン）
await tap('流局');
await expectText('荒牌平局');
await shot('draw');

// 戻ってホームから戦績と個人成績を開く
await tap('Back');
await tap('Back');
await tap('戦績');
await expectText('プレイヤー1');
await shot('history');
await tap('Back');
await tap('個人成績');
await expectText('この条件で終局した対局はまだありません');
await shot('stats');

// プライバシーポリシーのページ（ストアに登録する URL）
const policy = await page.goto(new URL('privacy.html', url).toString());
if (policy.status() !== 200) throw new Error(`privacy.html: ${policy.status()}`);
await expectText('プライバシーポリシー');
await expectText('1. 集める情報');

await browser.close();
const notGithub = [...external].filter((h) => h !== 'fonts.gstatic.com');
if (notGithub.length) throw new Error(`想定していない外部への接続: ${notGithub.join(', ')}`);
console.log('E2E OK', external.size ? `（外部: ${[...external].join(', ')}）` : '');
