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
def row(labels, left, top, height, tile_w, gaps=()):
    x = left * W + tile_w * 0.3; th = int(tile_w * 1.36); y = int(top * H + (height * H - th) / 2)
    for i, l in enumerate(labels):
        if i in gaps: x += tile_w * 0.8
        canvas.paste(crop(l).resize((tile_w, th), Image.LANCZOS), (int(W - x - tile_w), y)); x += tile_w + 2
tw = int(0.78 * W / 14.5)
# エリアの位置は lib/features/camera/guided_recognition.dart の GuideFrames と同じ（左・上・高さ）
small = int(tw * 0.8)  # ドラ表示牌のエリアは2段に置くので、少し小さく写る
row(['4p', '5s'], 0.02, 0.02, 0.15, small)                                   # ドラ表示牌 2枚（上の段）
row(['6p'], 0.02, 0.17, 0.15, small)                                         # 裏ドラ表示牌 1枚（下の段）
row(['7z', '7z', '7z', '2p', '3p', '4p'], 0.02, 0.34, 0.28, tw)              # 鳴いた牌（離さない）: 中のポン、2-3-4筒のチー
row(['2m', '3m', '4m', '5s', '5s', '6p', '7p'], 0.02, 0.64, 0.34, tw)        # 手牌 7枚
row(['8p'], 0.82, 0.64, 0.34, tw)                                            # 和了牌
canvas.save(out / 'frame.jpg', quality=90)
data = (out / 'frame.jpg').read_bytes()
(out / 'frame.jpg').unlink()
open(out / 'guided_camera.mjpeg', 'wb').write(data * 2)
print(src, (W, H), 'tile', tw)
