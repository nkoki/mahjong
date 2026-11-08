"""アプリのアイコン（Android・iOS・Web・ストア用）を作る。

デザイン: アプリの「卓ビュー」（lib/features/session/screens/table_layout.dart）を上から見た形。
木の枠と緑の卓、中央の盤（親の印の金色の点）、4人の前に置いた立直棒（千点棒）。
牌の絵は使わない（牌のアイコンの麻雀アプリが多く、見分けにくいため）。色はアプリと同じ。
ホーム画面の見出しの印（lib/shared/widgets/app_mark.dart）も同じデザイン。
色やデザインを変えたら、リポジトリのいちばん上で次を実行して作り直す。

  python tools/app_icon/make_icons.py

必要なもの: Pillow
"""

import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
FELT = (31, 74, 58)           # 卓の緑 = アプリのテーマの色（#1F4A3A）
VERMILION = (176, 53, 43)     # 朱色（#B0352B）。立直棒の点
BACKGROUND = (22, 56, 44)     # アイコンの背景（卓より少し暗い緑 #16382C。Android の ic_launcher_background と同じ）
WOOD_LIGHT = (110, 75, 42)    # 卓の木の枠（卓ビューと同じ #6E4B2A → #4A3019）
WOOD_DARK = (74, 48, 25)
PANEL = (15, 31, 25)          # 卓ビューの中央の盤（#0F1F19）
PANEL_EDGE = (47, 85, 69)     # 盤の縁（#2F5545）
GOLD = (255, 210, 122)        # 盤の文字の金色（#FFD27A）。親の印
STICK = (255, 252, 244)       # 点棒（#FFFCF4）

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


def _stick(d: ImageDraw.ImageDraw, cx: float, cy: float, length: float, thick: float, vertical: bool):
    """千点棒（立直棒）: 生成りの棒の中央に朱色の点"""
    if vertical:
        box = [cx - thick / 2, cy - length / 2, cx + thick / 2, cy + length / 2]
    else:
        box = [cx - length / 2, cy - thick / 2, cx + length / 2, cy + thick / 2]
    d.rounded_rectangle(box, thick / 2, fill=STICK)
    r = thick * 0.3
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=VERMILION)


def _shadow(layer: Image.Image, S: int, alpha: float = 0.5) -> Image.Image:
    """下に少しずらしてぼかした影を付ける"""
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.putalpha(layer.split()[3].point(lambda v: round(v * alpha)))
    shadow = shadow.transform((S, S), Image.AFFINE, (1, 0, 0, 0, 1, -S * 0.012)).filter(
        ImageFilter.GaussianBlur(S * 0.012))
    return Image.alpha_composite(shadow, layer)


def table_layer(size: int, scale: float) -> Image.Image:
    """透明な背景に、上から見た卓を描く（アプリの「卓ビュー」と同じ作り）。
    木の枠・緑の卓・中央の盤（親の印の金色の点）・4人の前に置いた立直棒。scale は枠の幅（画像に対する割合）"""
    S = size * SS
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    c = S / 2
    half = S * scale / 2
    u = S * scale  # 卓の大きさを基準にした長さ
    # 木の枠（上が明るく下が暗い）
    rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rim)
    for i in range(64):
        t = i / 63
        col = tuple(round(a + (b - a) * t) for a, b in zip(WOOD_LIGHT, WOOD_DARK))
        y = c - half + 2 * half * t
        rd.line([(c - half, y), (c + half, y)], fill=col + (255,), width=max(1, round(2 * half / 60)))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([c - half, c - half, c + half, c + half], u * 0.09, fill=255)
    layer.paste(rim, (0, 0), mask)
    # 緑の卓（布の目つき）
    inner = half - u * 0.06
    cloth = felt(S).convert("RGBA")
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([c - inner, c - inner, c + inner, c + inner], u * 0.05, fill=255)
    layer.paste(cloth, (0, 0), mask)
    # 中央の盤と立直棒（影を付けて卓から少し浮かせる）
    top = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(top)
    p = u * 0.17
    d.rounded_rectangle([c - p, c - p, c + p, c + p], u * 0.04, fill=PANEL, outline=PANEL_EDGE,
                        width=max(1, round(u * 0.016)))
    r = u * 0.045
    d.ellipse([c - r, c - r, c + r, c + r], fill=GOLD)
    gap, length, thick = u * 0.29, u * 0.36, u * 0.062
    _stick(d, c, c + gap, length, thick, False)
    _stick(d, c, c - gap, length, thick, False)
    _stick(d, c - gap, c, length, thick, True)
    _stick(d, c + gap, c, length, thick, True)
    layer = Image.alpha_composite(layer, _shadow(top, S))
    return _shadow(layer, S, 0.35).resize((size, size), Image.LANCZOS)


def full_icon(size: int, scale: float = 0.74) -> Image.Image:
    """背景つきのアイコン（四角いまま。角の丸めは端末が行う）。背景は卓より少し暗い緑"""
    img = Image.new("RGBA", (size, size), BACKGROUND + (255,))
    img = Image.alpha_composite(img, table_layer(size, scale))
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
        save(table_layer(px, 0.6), f"android/app/src/main/res/mipmap-{name}/ic_launcher_foreground.png")
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
    maskable = full_icon(1024, scale=0.6)
    save(maskable.resize((192, 192), Image.LANCZOS), "web/icons/Icon-maskable-192.png")
    save(maskable.resize((512, 512), Image.LANCZOS), "web/icons/Icon-maskable-512.png")
    save(full_icon(64, scale=0.94).resize((16, 16), Image.LANCZOS), "web/favicon.png")
    # iOS の起動画面の中央の画像（背景は LaunchScreen.storyboard で緑にしている）
    for suffix, px in [("", 168), ("@2x", 336), ("@3x", 504)]:
        save(table_layer(px, 0.9), f"ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png")


if __name__ == "__main__":
    main()
