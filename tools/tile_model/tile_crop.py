"""牌を1枚ずつ見分ける分類モデル（tile_classifier.tflite）に渡す画像の切り抜き方。

学習（train_classifier.py）・評価（evaluate.py）・アプリ（lib/features/camera/tile_classifier.dart の
classifierCropRect）で同じ切り抜き方にする。変えるときは3か所とも直す。

  1. 検出した箱（ピクセル）を、上下左右に箱の幅・高さの MARGIN ずつ広げる（写真の外は切り捨てる）
  2. 箱が横長（幅 > 高さ × LANDSCAPE_RATIO。横向きに置いた牌）なら、時計回りに 90 度回して縦長にする
  3. 幅 INPUT_W × 高さ INPUT_H に縮める（縦横比は変える）。画素値は 0〜255 のまま渡す
"""

import math

from PIL import Image

INPUT_H = 128
INPUT_W = 96
MARGIN = 0.08
LANDSCAPE_RATIO = 1.15


def crop_rect(left, top, right, bottom, width, height, margin=MARGIN):
    """箱（ピクセル）→ 切り抜く範囲 (x, y, w, h) と、時計回りに 90 度回すかどうか"""
    bw, bh = right - left, bottom - top
    l = max(0, math.floor(left - bw * margin))
    t = max(0, math.floor(top - bh * margin))
    r = min(width, math.ceil(right + bw * margin))
    b = min(height, math.ceil(bottom + bh * margin))
    rotate = bw > bh * LANDSCAPE_RATIO
    return (l, t, max(1, r - l), max(1, b - t)), rotate


def classifier_input(image: Image.Image, left, top, right, bottom):
    """アプリと同じ切り抜き方で、分類モデルに渡す画像（INPUT_W × INPUT_H、RGB）を作る。座標はピクセル"""
    (x, y, w, h), rotate = crop_rect(left, top, right, bottom, image.width, image.height)
    crop = image.convert("RGB").crop((x, y, x + w, y + h))
    if rotate:
        crop = crop.transpose(Image.Transpose.ROTATE_270)  # 時計回りに 90 度
    return crop.resize((INPUT_W, INPUT_H), Image.BOX)


def dump_fixture(out_dir):
    """アプリのテスト用データ（test/fixtures/）を書く。

    向きの分かる模様の画像と、いくつかの箱について、切り抜く範囲・回すかどうか・分類モデルへの入力を書く。
    """
    import json
    from pathlib import Path

    import numpy as np

    out_dir = Path(out_dir)
    w, h = 240, 180
    yy, xx = np.mgrid[0:h, 0:w]
    # 赤は左→右、緑は上→下に明るくなる（回す向きや上下左右が違えばずれる）。青はなめらかな波。
    # くっきりした境目は縮小・拡大のしかたの違いで値がずれるので入れない
    blue = (np.sin(xx / 17.0) * np.cos(yy / 23.0) + 1) * 127.5
    arr = np.stack([xx * 255 / (w - 1), yy * 255 / (h - 1), blue], -1).round()
    Image.fromarray(arr.astype(np.uint8)).save(out_dir / "classifier_crop_image.png")
    image = Image.open(out_dir / "classifier_crop_image.png")
    cases = []
    for box in [(20, 10, 60, 70), (100, 40, 190, 90), (0, 0, 30, 40), (200, 140, 240, 180), (50.5, 20.2, 80.7, 61.9)]:
        (x, y, cw, ch), rotate = crop_rect(*box, w, h)
        pixels = np.asarray(classifier_input(image, *box), np.uint8)
        cases.append({
            "box": [box[0] / w, box[1] / h, box[2] / w, box[3] / h],
            "x": x, "y": y, "width": cw, "height": ch, "rotate": rotate,
            "input_mean": [float(v) for v in pixels.reshape(-1, 3).mean(0)],
            # 4×3 のマスごとの平均（向きが違えばずれる）
            "input_grid": [float(v) for v in pixels.reshape(4, INPUT_H // 4, 3, INPUT_W // 3, 3).mean((1, 3)).ravel()],
        })
    (out_dir / "classifier_crop_fixture.json").write_text(json.dumps(
        {"image_width": w, "image_height": h, "input_height": INPUT_H, "input_width": INPUT_W, "cases": cases},
        indent=1))
    print(f"wrote {out_dir}/classifier_crop_fixture.json")


if __name__ == "__main__":
    import argparse

    ap = argparse.ArgumentParser(description="アプリのテスト用データを書く")
    ap.add_argument("--dump-fixture", required=True, help="書き出すフォルダ（test/fixtures）")
    dump_fixture(ap.parse_args().dump_fixture)
