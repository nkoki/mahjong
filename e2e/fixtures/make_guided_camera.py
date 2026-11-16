"""枠つきの撮影の確認用の映像（1コマの写真を並べた MJPEG）を作る。

ブラウザの確認用の偽のカメラは「内側のカメラ」として扱われ、映像が鏡のように左右反転して表示される。
そこで、牌は左右を入れ替えた位置に置く（画面では、枠の中に牌が入って見える）。
使い方: python e2e/fixtures/make_guided_camera.py <HUST の valid フォルダ> e2e/fixtures
（HUST のデータは tools/tile_model/fetch_roboflow.py で取得する。必要なもの: pillow numpy）"""
import json, sys
from pathlib import Path
from PIL import Image
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools' / 'tile_model'))
from classes import normalize_label
root = Path(sys.argv[1]); out = Path(sys.argv[2])
W, H = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) > 4 else (1920, 1080)
coco = json.load(open(root / '_annotations.coco.json'))
cats = {c['id']: normalize_label(c['name']) for c in coco['categories']}
files = {im['id']: im for im in coco['images']}
need = ['7z', '2p', '3p', '4p', '2m', '3m', '4m', '5s', '6p', '7p', '8p']
by = {}
for a in coco['annotations']:
    l = cats[a['category_id']]
    if l and a['bbox'][3] > a['bbox'][2] * 1.1:
        by.setdefault(a['image_id'], {}).setdefault(l, []).append(a['bbox'])
best = next(i for i, d in sorted(by.items()) if all(k in d for k in need))
src = files[best]['file_name']
img = Image.open(root / src).convert('RGB')
fill = tuple(int(v) for v in np.median(np.asarray(img).reshape(-1, 3), axis=0))
canvas = Image.new('RGB', (W, H), fill)
def crop(label):
    x, y, w, h = by[best][label][0]
    return img.crop((int(x), int(y), int(x + w), int(y + h)))

# 撮影画面の作り（lib/features/camera/guided_camera_screen.dart・guided_recognition.dart と同じ計算）。
# 確認のときのブラウザの画面は 幅 800 × 高さ 860。映像は画面いっぱいに広げ、はみ出す左右は見えない。
# エリアは、上 52・下 118 を除いた範囲に GuideFrames の割合で置く
VIEW_W, VIEW_H, TOP, BOTTOM = 800, 860, 52, 118
FRAMES = {  # GuideFrames（左, 上, 幅, 高さ）
    'dora': (0.02, 0.02, 0.96, 0.24),
    'melds': (0.02, 0.28, 0.96, 0.24),
    'hand': (0.02, 0.54, 0.78, 0.44),
    'win': (0.82, 0.54, 0.16, 0.44),
}
def photo_rect(name):
    """エリアが写真の中で占める範囲（ピクセル: 左, 上, 幅, 高さ）"""
    l, t, w, h = FRAMES[name]
    gh = VIEW_H - TOP - BOTTOM
    t, h = (TOP + t * gh) / VIEW_H, h * gh / VIEW_H          # guideRegionsInView
    view_aspect, photo_aspect = VIEW_W / VIEW_H, W / H
    sx = sy = 1.0                                             # mapViewRegionToPhoto
    if photo_aspect > view_aspect: sx = view_aspect / photo_aspect
    else: sy = photo_aspect / view_aspect
    return (((1 - sx) / 2 + l * sx) * W, ((1 - sy) / 2 + t * sy) * H, w * sx * W, h * sy * H)

def row(labels, name, tile_w, part=(0.0, 1.0)):
    """エリア [name] の中に牌を左から並べる。part は、エリアの高さのうち使う範囲（上の段・下の段）"""
    left, top, width, height = photo_rect(name)
    th = int(tile_w * 1.36)
    y = int(top + height * part[0] + (height * (part[1] - part[0]) - th) / 2)
    x = left + min(tile_w * 0.3, max(0, (width - tile_w) / 2))
    for l in labels:
        # 偽のカメラは鏡のように左右反転して表示されるので、左右を入れ替えた位置に置く
        canvas.paste(crop(l).resize((tile_w, th), Image.LANCZOS), (int(W - x - tile_w), y)); x += tile_w + 2

tw = int(photo_rect('hand')[2] / 9)
small = int(tw * 0.62)  # ドラ表示牌のエリアは2段に置くので小さめに置き、上下の段の間を空ける
row(['4p', '5s'], 'dora', small, part=(0.0, 0.5))                 # ドラ表示牌 2枚（上の段）
row(['6p'], 'dora', small, part=(0.5, 1.0))                       # 裏ドラ表示牌 1枚（下の段）
row(['7z', '7z', '7z', '2p', '3p', '4p'], 'melds', tw)            # 鳴いた牌（離さない）: 中のポン、2-3-4筒のチー
row(['2m', '3m', '4m', '5s', '5s', '6p', '7p'], 'hand', tw)       # 手牌 7枚
row(['8p'], 'win', tw)                                            # 和了牌
canvas.save(out / 'frame.jpg', quality=90)
data = (out / 'frame.jpg').read_bytes()
(out / 'frame.jpg').unlink()
open(out / 'guided_camera.mjpeg', 'wb').write(data * 2)
print(src, (W, H), 'tile', tw)
