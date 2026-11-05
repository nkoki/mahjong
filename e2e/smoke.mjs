// Web 版を実際のブラウザで動かして、主な操作が通るかを確かめる（E2E テスト）。
//
// 使い方（リポジトリのいちばん上で）:
//   flutter build web --release --no-web-resources-cdn --base-href /mahjong/
//   mkdir -p /tmp/site && cp -r build/web /tmp/site/mahjong && (cd /tmp/site && python3 -m http.server 8765 &)
//   cd e2e && npm ci && npx playwright install chromium && node smoke.mjs http://localhost:8765/mahjong/
//
// Flutter の Web 版は画面を canvas に描くので、読み上げ用の情報（セマンティクス）を有効にしてから、
// ボタンなどを名前で探して操作する。
import { chromium } from 'playwright';

const url = process.argv[2] ?? 'http://localhost:8765/mahjong/';
const shotDir = process.argv[3];
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 400, height: 860 } });
const external = new Set();
page.on('request', (r) => {
  const u = new URL(r.url());
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
async function expectText(text) {
  for (let i = 0; i < 20; i++) {
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
