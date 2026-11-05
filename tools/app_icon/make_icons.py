"""アプリのアイコン（Android・iOS・Web・ストア用）を作る。

デザイン: 緑の卓の上に、象牙色の牌を1枚置いたもの（牌の面は丸の模様。特定の牌の絵柄は写していない）。
色やデザインを変えたら、リポジトリのいちばん上で次を実行して作り直す。

  python tools/app_icon/make_icons.py

必要なもの: Pillow
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
FELT_TOP = (46, 125, 50)      # 卓の緑（上）
FELT_BOTTOM = (27, 94, 32)    # 卓の緑（下）= アプリのテーマの色（#1B5E20）
IVORY = (250, 246, 232)
TILE_BACK = (240, 182, 40)    # 牌の背（黄）
RED = (198, 40, 40)
GREEN = (27, 94, 32)
NAVY = (21, 57, 110)

SS = 4  # なめらかに描くための拡大率


def felt(size: int) -> Image.Image:
    """卓の布（上から下へ少し暗くなる緑）"""
    img = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(FELT_TOP, FELT_BOTTOM))
        d.line([(0, y), (size, y)], fill=c)
    return img


def tile_layer(size: int, scale: float) -> Image.Image:
    """透明な背景に牌を1枚描く。scale は牌の高さ（画像の高さに対する割合）"""
    S = size * SS
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    h = S * scale
    w = h * 0.74
    x0, y0 = (S - w) / 2, (S - h) / 2 - h * 0.03
    r = w * 0.16
    # 影
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [x0 + w * 0.04, y0 + h * 0.08, x0 + w * 1.04, y0 + h * 1.06], r, fill=(0, 0, 0, 110))
    layer = Image.alpha_composite(layer, shadow.filter(ImageFilter.GaussianBlur(S * 0.02)))
    d = ImageDraw.Draw(layer)
    # 牌の背（下の厚み）と表面
    d.rounded_rectangle([x0, y0 + h * 0.06, x0 + w, y0 + h], r, fill=TILE_BACK)
    d.rounded_rectangle([x0, y0, x0 + w, y0 + h * 0.9], r, fill=IVORY)
    # 面の模様: 大きな丸（外側から 緑・白・紺・白・赤）
    cx, cy = x0 + w / 2, y0 + h * 0.45
    for rad, color in [(0.36, GREEN), (0.30, IVORY), (0.25, NAVY), (0.19, IVORY), (0.14, RED)]:
        rr = w * rad
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=color)
    # 丸のまわりの小さな飾り（8つ）
    import math
    for k in range(8):
        a = math.pi * 2 * k / 8
        px, py = cx + math.cos(a) * w * 0.33, cy + math.sin(a) * w * 0.33
        rr = w * 0.025
        d.ellipse([px - rr, py - rr, px + rr, py + rr], fill=IVORY)
    return layer.resize((size, size), Image.LANCZOS)


def full_icon(size: int, scale: float = 0.66) -> Image.Image:
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
