"""アプリのアイコン（Android・iOS・Web・ストア用）を作る。

デザイン: 卓の緑（布の細かい目だけで、色の移り変わりは付けない）の上に、「中」の牌を1枚、少し傾けて置いたもの。
「中」の字はフォントを使わず、太い線（縦の線と口の形）を組み合わせて描いている。
牌の背はアプリの牌（lib/shared/widgets/tile_painter.dart）と同じ緑。
色やデザインを変えたら、リポジトリのいちばん上で次を実行して作り直す。

  python tools/app_icon/make_icons.py

必要なもの: Pillow
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
FELT = (31, 74, 58)           # 卓の緑 = アプリのテーマの色（#1F4A3A）
IVORY = (251, 248, 238)       # 牌の面
IVORY_SHADE = (232, 224, 205)  # 牌の面の下の陰
TILE_BACK = (30, 122, 87)     # 牌の背（緑）
VERMILION = (176, 53, 43)     # 中の朱色（#B0352B）

SS = 4  # なめらかに描くための拡大率


def felt(size: int) -> Image.Image:
    """卓の布（同じ緑に、ごく細かい目を付ける。毎回同じになるよう乱数の種は固定）"""
    img = Image.new("RGB", (size, size), FELT)
    px = img.load()
    rnd = random.Random(7)
    for y in range(size):
        for x in range(size):
            d = rnd.randint(-5, 5)
            r, g, b = FELT
            px[x, y] = (r + d, g + d, b + d)
    return img.filter(ImageFilter.GaussianBlur(max(0.4, size / 1400)))


def tile_layer(size: int, scale: float, angle: float = -8) -> Image.Image:
    """透明な背景に「中」の牌を1枚描く。scale は牌の高さ（画像の高さに対する割合）、angle は傾き（度）"""
    S = size * SS
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    h = S * scale
    w = h * 0.74
    x0, y0 = (S - w) / 2, (S - h) / 2
    r = w * 0.13
    thick = h * 0.09
    d = ImageDraw.Draw(layer)
    # 牌の背（厚み）と面
    d.rounded_rectangle([x0, y0, x0 + w, y0 + h], r, fill=TILE_BACK)
    face_h = h - thick
    d.rounded_rectangle([x0, y0, x0 + w, y0 + face_h], r, fill=IVORY)
    # 面の下の方を少し陰らせる
    shade = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    for i in range(40):
        t = i / 39
        a = round(110 * t * t)
        yy = y0 + face_h * (0.6 + 0.4 * t)
        sd.line([(x0, yy), (x0 + w, yy)], fill=IVORY_SHADE + (a,), width=max(1, round(face_h * 0.012)))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([x0, y0, x0 + w, y0 + face_h], r, fill=255)
    layer.paste(shade, (0, 0), Image.composite(shade, Image.new("RGBA", (S, S)), mask).split()[3])
    d = ImageDraw.Draw(layer)
    # 「中」: 口の形（太い線の四角）と、上下に突き抜ける縦の線（筆で書いたように下へ少し細くする）
    cx = x0 + w / 2
    stroke = w * 0.135
    bx0, bx1 = x0 + w * 0.16, x0 + w * 0.84
    by0, by1 = y0 + face_h * 0.31, y0 + face_h * 0.63
    d.rounded_rectangle([bx0, by0, bx1, by1], stroke * 0.3, outline=VERMILION, width=round(stroke))
    top, bottom = y0 + face_h * 0.11, y0 + face_h * 0.89
    wt, wb = w * 0.17, w * 0.12
    d.polygon([(cx - wt / 2, top), (cx + wt / 2, top), (cx + wb / 2, bottom), (cx - wb / 2, bottom)], fill=VERMILION)
    d.ellipse([cx - wt / 2, top - wt * 0.18, cx + wt / 2, top + wt * 0.18], fill=VERMILION)
    d.ellipse([cx - wb / 2, bottom - wb * 0.3, cx + wb / 2, bottom + wb * 0.3], fill=VERMILION)
    # 傾けて、影を付ける
    layer = layer.rotate(angle, resample=Image.BICUBIC, center=(S / 2, S / 2))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    alpha = layer.split()[3].point(lambda v: round(v * 0.45))
    shadow.putalpha(alpha)
    shadow = shadow.transform((S, S), Image.AFFINE, (1, 0, -S * 0.012, 0, 1, -S * 0.022)).filter(
        ImageFilter.GaussianBlur(S * 0.018))
    out = Image.alpha_composite(shadow, layer)
    return out.resize((size, size), Image.LANCZOS)


def full_icon(size: int, scale: float = 0.64) -> Image.Image:
    """背景つきのアイコン（四角いまま。角の丸めは端末が行う）"""
    img = felt(size).convert("RGBA")
    img = Image.alpha_composite(img, tile_layer(size, scale))
    return img.convert("RGB")


def save(img: Image.Image, path: str):
    p = ROOT / path
    p.parent.mkdir(parents=True, exist_ok=True)
    img.save(p, optimize=True)
    print("wrote", path, img.size)


def main():
    master = full_icon(1024)
    # ストア用（Google Play は 512×512）
    save(master.resize((512, 512), Image.LANCZOS), "store/icon-512.png")
    # Android（従来のアイコン）
    for name, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
        save(full_icon(px * 4).resize((px, px), Image.LANCZOS), f"android/app/src/main/res/mipmap-{name}/ic_launcher.png")
    # Android 8 以降のアダプティブアイコン（前景 108dp。端末が形を切り抜くので、牌は中央の安全な範囲に収める）
    for name, px in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)]:
        save(tile_layer(px, 0.56), f"android/app/src/main/res/mipmap-{name}/ic_launcher_foreground.png")
    # iOS（透明な部分があってはいけないので RGB）
    for size, scale in [(20, 1), (20, 2), (20, 3), (29, 1), (29, 2), (29, 3), (40, 1), (40, 2), (40, 3),
                        (60, 2), (60, 3), (76, 1), (76, 2), (83.5, 2), (1024, 1)]:
        px = round(size * scale)
        label = f"{size:g}x{size:g}@{scale}x"
        save(master.resize((px, px), Image.LANCZOS), f"ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-{label}.png")
    # Web
    save(master.resize((192, 192), Image.LANCZOS), "web/icons/Icon-192.png")
    save(master.resize((512, 512), Image.LANCZOS), "web/icons/Icon-512.png")
    # マスカブル（端末が丸などに切り抜く）用は、牌を小さめにして余白を取る
    maskable = full_icon(1024, scale=0.52)
    save(maskable.resize((192, 192), Image.LANCZOS), "web/icons/Icon-maskable-192.png")
    save(maskable.resize((512, 512), Image.LANCZOS), "web/icons/Icon-maskable-512.png")
    save(full_icon(64, scale=0.8).resize((16, 16), Image.LANCZOS), "web/favicon.png")
    # iOS の起動画面の中央の画像（背景は LaunchScreen.storyboard で緑にしている）
    for suffix, px in [("", 168), ("@2x", 336), ("@3x", 504)]:
        save(tile_layer(px, 0.9), f"ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png")


if __name__ == "__main__":
    main()
