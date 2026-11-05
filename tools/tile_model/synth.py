"""FluffyStuff/riichi-mahjong-tiles（CC0）の牌画像から、手牌を撮った写真に似せた合成画像を作る。

出力は MediaPipe Model Maker が読める COCO 形式:
  <out>/images/*.jpg
  <out>/labels.json   （categories の id 0 は background）

使い方:
  python synth.py --tiles <riichi-mahjong-tiles の Export/Regular> --out data/synth --count 3000
"""

import argparse
import json
import math
import random
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

import sys  # noqa: E402

# python -I で動かしても同じフォルダの classes.py を読めるようにする
sys.path.insert(0, str(Path(__file__).resolve().parent))
from classes import CLASSES, FLUFFY_FILES

# 牌の背の色（黄・青・緑・橙・赤・黒・灰）
BACK_COLORS = [
    (236, 186, 52), (40, 90, 170), (30, 120, 70), (225, 120, 40),
    (170, 40, 45), (40, 40, 45), (150, 150, 155), (70, 160, 200),
]
# 紛らわしいものとして置く牌の背の色。灰色・黒は使わない（色の薄い背は白（5z）と見分けにくく、
# 白を「牌ではない」と覚えさせてしまうため）
DISTRACTOR_BACK_COLORS = [
    (236, 186, 52), (40, 90, 170), (30, 120, 70), (225, 120, 40), (170, 40, 45), (70, 160, 200),
]
# 卓・マットの色
MAT_COLORS = [
    (30, 110, 60), (20, 80, 50), (40, 70, 130), (25, 50, 100), (90, 90, 95),
    (150, 110, 70), (120, 80, 50), (200, 190, 170), (235, 235, 230), (50, 50, 55), (110, 30, 40),
]


def load_faces(tiles_dir: Path):
    """各牌の表面（Front に絵柄を重ねたもの）を RGBA で読み込む"""
    front = Image.open(tiles_dir / "Front.png").convert("RGBA")
    faces = {}
    for fname, label in FLUFFY_FILES.items():
        sym = Image.open(tiles_dir / f"{fname}.png").convert("RGBA")
        face = front.copy()
        face.alpha_composite(sym)
        faces[label] = face
    back = Image.open(tiles_dir / "Back.png").convert("RGBA")
    return faces, front, back


def vary_face(face: Image.Image, rng: random.Random) -> Image.Image:
    """牌の色味・明るさを少し変える（象牙色・白・黄ばみ）"""
    img = face
    arr = np.asarray(img).astype(np.float32)
    tint = np.array([rng.uniform(0.9, 1.05), rng.uniform(0.9, 1.03), rng.uniform(0.82, 1.02)])
    arr[..., :3] = np.clip(arr[..., :3] * tint, 0, 255)
    img = Image.fromarray(arr.astype(np.uint8), "RGBA")
    img = ImageEnhance.Contrast(img).enhance(rng.uniform(0.75, 1.15))
    return img


def make_tile_sprite(face: Image.Image, w: int, rng: random.Random, band: float, back_color, upright: bool):
    """牌1枚の画像を作る。

    band: 手前の側面（厚み）の高さ（牌の幅に対する比率）。0 なら真上から見た形。
    upright: 立てた牌を手前から見た形（表面の上に背の色が少し見える）
    戻り値: RGBA 画像（牌の外側は透明）
    """
    h = int(round(w * rng.uniform(1.28, 1.40)))
    f = vary_face(face, rng).resize((w, h), Image.LANCZOS)
    bh = int(round(w * band))
    top = int(round(w * rng.uniform(0.05, 0.18))) if upright else 0
    sprite = Image.new("RGBA", (w, h + bh + top), (0, 0, 0, 0))
    if top:
        sprite.paste(Image.new("RGBA", (w, top + 4), back_color + (255,)), (0, 0))
    if bh:
        ivory = int(rng.uniform(200, 240))
        body_h = int(bh * rng.uniform(0.4, 0.7))
        body = Image.new("RGBA", (w, body_h + 4), (ivory, ivory - 5, ivory - 20, 255))
        backb = Image.new("RGBA", (w, bh - body_h + 4), back_color + (255,))
        sprite.paste(backb, (0, top + h + body_h - 4))
        sprite.paste(body, (0, top + h - 4))
        # 角を丸めたように見せるため、透明にした Front の形で切り抜く
    sprite.alpha_composite(f, (0, top))
    # 上下方向の明るさの変化
    arr = np.asarray(sprite).astype(np.float32)
    grad = np.linspace(rng.uniform(0.9, 1.08), rng.uniform(0.85, 1.05), arr.shape[0])[:, None, None]
    arr[..., :3] = np.clip(arr[..., :3] * grad, 0, 255)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def make_background(W: int, H: int, rng: random.Random, np_rng: np.random.Generator) -> np.ndarray:
    """卓・マット・机などに似せた背景"""
    base = np.array(rng.choice(MAT_COLORS), dtype=np.float32)
    base = np.clip(base + np_rng.normal(0, 18, 3), 0, 255)
    img = np.ones((H, W, 3), np.float32) * base
    # ざらざらした布の模様
    for scale in (4, 16, 64):
        n = np_rng.normal(0, 1, (H // scale + 2, W // scale + 2)).astype(np.float32)
        n = cv2.resize(n, (W, H), interpolation=cv2.INTER_CUBIC)
        img += n[..., None] * rng.uniform(2, 9)
    # 木目
    if rng.random() < 0.2:
        ys = np.arange(H, dtype=np.float32)[:, None]
        xs = np.arange(W, dtype=np.float32)[None, :]
        wave = np.sin(ys / rng.uniform(6, 20) + np.sin(xs / rng.uniform(80, 200)) * 3)
        img += wave[..., None] * rng.uniform(6, 18)
    # 線（マットの縁・机の境目）
    for _ in range(rng.choice([0, 0, 1, 2])):
        c = tuple(float(v) for v in np.clip(base + np_rng.normal(0, 60, 3), 0, 255))
        p1 = (rng.randint(0, W), rng.randint(0, H))
        p2 = (rng.randint(0, W), rng.randint(0, H))
        cv2.line(img, p1, p2, c, rng.randint(2, 12))
    return np.clip(img, 0, 255)


def layout_hand(faces, back, rng: random.Random, W: int, H: int):
    """透明な板の上に手牌を並べる。戻り値: (RGBA 画像, [(label, x0, y0, x1, y1)])"""
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow = Image.new("L", (W, H), 0)
    boxes = []

    n_tiles = rng.choice([14, 14, 14, 13, 13, 11, 8, 5, 3, 1]) if rng.random() < 0.9 else rng.randint(1, 18)
    labels = []
    counts = {}
    while len(labels) < n_tiles:
        t = rng.choice(CLASSES)
        base = t[:2]
        if counts.get(base, 0) >= 4:
            continue
        # 同じ牌を続けて並べることも多い（対子・刻子）
        k = rng.choice([1, 1, 1, 2, 3])
        for _ in range(k):
            if len(labels) < n_tiles and counts.get(base, 0) < 4:
                labels.append(t)
                counts[base] = counts.get(base, 0) + 1
    if rng.random() < 0.5:
        labels.sort(key=lambda t: CLASSES.index(t[:2]) + (0.5 if t.endswith("r") else 0))

    span = (rng.uniform(0.75, 0.98) if rng.random() < 0.8 else rng.uniform(0.4, 0.75)) * W
    gap_ratio = rng.uniform(0.0, 0.06)
    w = int(span / (n_tiles + 0.6 + n_tiles * gap_ratio))
    w = max(18, min(w, int(H * 0.6 / 1.35)))
    band = rng.choice([0.0, rng.uniform(0.1, 0.25), rng.uniform(0.25, 0.5)])
    upright = band == 0 and rng.random() < 0.4
    back_color = rng.choice(BACK_COLORS)

    gap = int(w * gap_ratio)
    x = int(rng.uniform(0.02, 0.4) * (W - n_tiles * (w + gap)))
    x = max(2, x)
    baseline = int(rng.uniform(0.35, 0.85) * H)
    sideways_idx = set()
    if rng.random() < 0.25 and n_tiles >= 4:
        sideways_idx.add(rng.randrange(n_tiles))
    win_gap = rng.random() < 0.4

    for i, lab in enumerate(labels):
        if win_gap and i == n_tiles - 1 and n_tiles > 1:
            x += int(w * rng.uniform(0.2, 1.0))
        sprite = make_tile_sprite(faces[lab], w, rng, band, back_color, upright)
        if i in sideways_idx:
            sprite = sprite.rotate(rng.choice([90, -90]), expand=True)
        sx, sy = sprite.size
        y = baseline - sy + int(rng.uniform(-0.02, 0.02) * w)
        if x + sx >= W - 2 or y < 0:
            break
        # 影
        off = int(w * rng.uniform(0.0, 0.12))
        shadow.paste(int(rng.uniform(60, 160)), (x + off, y + off, x + sx + off, y + sy + off))
        layer.alpha_composite(sprite, (x, y))
        boxes.append((lab, x, y, x + sx, y + sy))
        x += sx + gap

    # 2段目（鳴いた牌やドラ表示牌）を別の高さに置く
    if rng.random() < 0.3:
        n2 = rng.randint(1, 5)
        w2 = int(w * rng.uniform(0.7, 1.1))
        x2 = int(rng.uniform(0.02, 0.5) * W)
        y2 = int(rng.uniform(0.02, 0.25) * H) if baseline > H * 0.55 else int(baseline + w * 0.6)
        for _ in range(n2):
            lab = rng.choice(CLASSES)
            if counts.get(lab[:2], 0) >= 4:
                continue
            counts[lab[:2]] = counts.get(lab[:2], 0) + 1
            sprite = make_tile_sprite(faces[lab], w2, rng, band, back_color, False)
            sx, sy = sprite.size
            if x2 + sx >= W - 2 or y2 + sy >= H - 2:
                break
            if any(not (x2 + sx < b[1] or x2 > b[3] or y2 + sy < b[2] or y2 > b[4]) for b in boxes):
                break
            layer.alpha_composite(sprite, (x2, y2))
            boxes.append((lab, x2, y2, x2 + sx, y2 + sy))
            x2 += sx + gap

    # 牌の背（ラベルなし。紛らわしいものとして置く）
    if rng.random() < 0.3:
        bw = int(w * rng.uniform(0.7, 1.1))
        bsp = back.resize((bw, int(bw * 1.33)))
        arr = np.asarray(bsp).copy()
        arr[..., :3] = (np.array(rng.choice(DISTRACTOR_BACK_COLORS)) * 0.85 + arr[..., :3] * 0.15).astype(np.uint8)
        bsp = Image.fromarray(arr, "RGBA")
        bx, by = rng.randint(0, max(1, W - bw)), rng.randint(0, max(1, H - bsp.size[1]))
        if all(bx + bw < b[1] or bx > b[3] or by + bsp.size[1] < b[2] or by > b[4] for b in boxes):
            layer.alpha_composite(bsp, (bx, by))

    if rng.random() < 0.08:  # 反対側から撮った写真
        layer = layer.rotate(180)
        shadow = shadow.rotate(180)
        boxes = [(l, W - x1, H - y1, W - x0, H - y0) for (l, x0, y0, x1, y1) in boxes]
    shadow = shadow.filter(ImageFilter.GaussianBlur(max(1, w * 0.1)))
    return layer, shadow, boxes


def random_homography(W: int, H: int, rng: random.Random):
    """斜めから撮ったように見せる射影変換"""
    d = rng.uniform(0.0, 0.18)
    src = np.float32([[0, 0], [W, 0], [W, H], [0, H]])
    top_shrink = rng.uniform(0, d) * W
    dst = np.float32([
        [top_shrink + rng.uniform(-0.03, 0.03) * W, rng.uniform(0, 0.05) * H],
        [W - top_shrink + rng.uniform(-0.03, 0.03) * W, rng.uniform(0, 0.05) * H],
        [W + rng.uniform(-0.03, 0.03) * W, H - rng.uniform(0, 0.05) * H],
        [rng.uniform(-0.03, 0.03) * W, H - rng.uniform(0, 0.05) * H],
    ])
    M = cv2.getPerspectiveTransform(src, dst)
    ang = rng.uniform(-12, 12) if rng.random() < 0.7 else rng.uniform(-30, 30)
    R = cv2.getRotationMatrix2D((W / 2, H / 2), ang, rng.uniform(0.85, 1.1))
    R = np.vstack([R, [0, 0, 1]])
    return (R @ M).astype(np.float64)


def make_sample(faces, front, back, rng: random.Random, np_rng: np.random.Generator):
    aspect = rng.choice([4 / 3, 16 / 9, 3 / 2, 1.0, 3 / 4])
    W = 960
    H = int(W / aspect)
    bg = make_background(W, H, rng, np_rng)
    layer, shadow, boxes = layout_hand(faces, back, rng, W, H)

    M = random_homography(W, H, rng)
    lay = cv2.warpPerspective(np.asarray(layer), M, (W, H), flags=cv2.INTER_LINEAR)
    sh = cv2.warpPerspective(np.asarray(shadow), M, (W, H)).astype(np.float32) / 255.0
    img = bg * (1 - sh[..., None] * 0.6)
    a = lay[..., 3:4].astype(np.float32) / 255.0
    img = img * (1 - a) + lay[..., :3].astype(np.float32) * a

    # 照明（明るさのむら・色温度）
    gx = np.linspace(rng.uniform(0.6, 1.2), rng.uniform(0.6, 1.2), W)[None, :]
    gy = np.linspace(rng.uniform(0.7, 1.2), rng.uniform(0.7, 1.2), H)[:, None]
    light = (gx * gy)[..., None] * np.array([rng.uniform(0.85, 1.1), 1.0, rng.uniform(0.8, 1.15)])
    img = img * light * rng.uniform(0.8, 1.2)
    if rng.random() < 0.3:  # 部分的な影（手やスマホの影）
        mask = np.zeros((H, W), np.float32)
        cx, cy = rng.randint(0, W), rng.randint(0, H)
        cv2.ellipse(mask, (cx, cy), (rng.randint(W // 6, W // 2), rng.randint(H // 6, H // 2)),
                    rng.uniform(0, 180), 0, 360, 1.0, -1)
        mask = cv2.GaussianBlur(mask, (0, 0), W / 20)
        img *= (1 - mask * rng.uniform(0.2, 0.5))[..., None]
    img = np.clip(img, 0, 255).astype(np.uint8)

    # ぼけ・手ぶれ・ノイズ
    r = rng.random()
    if r < 0.3:
        img = cv2.GaussianBlur(img, (0, 0), rng.uniform(0.5, 1.8))
    elif r < 0.4:
        k = rng.randint(3, 9)
        kernel = np.zeros((k, k), np.float32)
        kernel[k // 2, :] = 1.0 / k
        R = cv2.getRotationMatrix2D((k / 2, k / 2), rng.uniform(0, 180), 1)
        kernel = cv2.warpAffine(kernel, R, (k, k))
        kernel /= max(kernel.sum(), 1e-6)
        img = cv2.filter2D(img, -1, kernel)
    noise = np_rng.normal(0, rng.uniform(0, 8), img.shape)
    img = np.clip(img.astype(np.float32) + noise, 0, 255).astype(np.uint8)

    # 箱を変換
    anns = []
    for lab, x0, y0, x1, y1 in boxes:
        pts = np.float32([[x0, y0], [x1, y0], [x1, y1], [x0, y1]]).reshape(-1, 1, 2)
        tp = cv2.perspectiveTransform(pts, M).reshape(-1, 2)
        bx0, by0 = tp.min(0)
        bx1, by1 = tp.max(0)
        area = (bx1 - bx0) * (by1 - by0)
        cx0, cy0 = max(0, bx0), max(0, by0)
        cx1, cy1 = min(W, bx1), min(H, by1)
        if cx1 <= cx0 or cy1 <= cy0:
            continue
        if (cx1 - cx0) * (cy1 - cy0) < area * 0.6:
            continue
        anns.append((lab, float(cx0), float(cy0), float(cx1 - cx0), float(cy1 - cy0)))

    # 長辺 640 に縮小
    s = 640 / max(W, H)
    img = cv2.resize(img, (int(W * s), int(H * s)), interpolation=cv2.INTER_AREA)
    anns = [(l, x * s, y * s, w * s, h * s) for (l, x, y, w, h) in anns]
    return img, anns


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tiles", required=True, type=Path, help="riichi-mahjong-tiles/Export/Regular")
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--count", type=int, default=3000)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    np_rng = np.random.default_rng(args.seed)
    faces, front, back = load_faces(args.tiles)
    (args.out / "images").mkdir(parents=True, exist_ok=True)

    categories = [{"id": 0, "name": "background"}] + [{"id": i + 1, "name": c} for i, c in enumerate(CLASSES)]
    cat_id = {c: i + 1 for i, c in enumerate(CLASSES)}
    images, annotations = [], []
    for i in range(args.count):
        img, anns = make_sample(faces, front, back, rng, np_rng)
        name = f"synth_{args.seed}_{i:06d}.jpg"
        quality = rng.randint(45, 95)
        cv2.imwrite(str(args.out / "images" / name), cv2.cvtColor(img, cv2.COLOR_RGB2BGR),
                    [cv2.IMWRITE_JPEG_QUALITY, quality])
        images.append({"id": i + 1, "file_name": name, "width": img.shape[1], "height": img.shape[0]})
        for lab, x, y, w, h in anns:
            annotations.append({
                "id": len(annotations) + 1, "image_id": i + 1, "category_id": cat_id[lab],
                "bbox": [round(x, 2), round(y, 2), round(w, 2), round(h, 2)],
                "area": round(w * h, 2), "iscrowd": 0,
            })
        if (i + 1) % 200 == 0:
            print(f"{i + 1}/{args.count}")
    with open(args.out / "labels.json", "w") as f:
        json.dump({"images": images, "annotations": annotations, "categories": categories}, f)
    print(f"done: {len(images)} images, {len(annotations)} boxes")


if __name__ == "__main__":
    main()
