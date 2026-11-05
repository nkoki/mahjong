"""分類モデルに「牌ではない（bg）」を覚えさせるための例を集める。

  - 検出モデルが間違えて見つけたもの（正解の牌と重ならない検出。トレイの空いた所・模様など）
  - 牌の無い所からの切り抜き（牌くらいの大きさ）

merge.py の出力（labels.json と images/）に検出モデルを当てて集め、negatives.json に書く。
train_classifier.py の --negatives に渡す。

実写のデータセットには、ラベルの付いていない牌が写っていることがある（Riichi Mahjong Detection に多い）。
それを「牌ではない」と覚えさせると本物の牌を捨てるようになるので、次のようにする。
  - --skip-prefix のデータ（merge.py の --src の順番で s0_, s1_, ... が付く）からは集めない
  - --classifier を渡すと、--trusted-prefix 以外のデータでは、その分類モデルが確率 --max-tile-prob 以上で
    何かの牌だと答えたものを外す（ラベルの付いていない本物の牌の可能性が高い）
  - --classifier を渡すと、--trusted-prefix のデータ（合成）では、検出モデルが間違えて見つけたもののうち、
    色の薄いもの（彩度 --haku-like-saturation 未満）で、その分類モデルが確率 --haku-like-prob 以上で白（5z）だと
    答えたものを外す。合成データの紛らわしい牌の背のうち灰色のものは白と見分けにくく、「牌ではない」と覚えると
    本物の白を捨てるようになるため。色のはっきりした牌の背は外さない（暗槓などの牌の背を白と読まないように）。
    実写のデータでは外さない（トレイの空いた所なども白と答えるが、それは「牌ではない」と覚えさせたい）
  - --label-negatives で、元のデータセットでラベルの付いた「牌ではないもの」（Riichi Mahjong Detection の
    牌の背 0z など）も加える

使い方:
  python mine_negatives.py --model out --data data/train --out data/train/negatives.json \
      --classifier out_cls_first --trusted-prefix s0_ --skip-prefix s2_ \
      --label-negatives data/roboflow/riichi_detection/train:s2_:0z
  （out_cls_first は「牌ではない」なしで先に学習した分類モデル）
"""

import argparse
import json
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import evaluate  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True, type=Path, help="検出モデル（train.py の出力のフォルダ）")
    ap.add_argument("--data", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--threshold", type=float, default=0.1, help="この確信度以上の検出を集める（低めにして難しい例も集める）")
    ap.add_argument("--max-iou", type=float, default=0.2, help="正解の牌との重なりがこれ未満なら「牌ではない」とする")
    ap.add_argument("--per-image", type=int, default=6, help="1枚の写真から集める間違いの検出の上限")
    ap.add_argument("--random-per-image", type=float, default=0.5, help="1枚の写真から切り抜く背景の数（平均）")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--skip-prefix", nargs="*", default=[], help="集めないデータのファイル名の頭（ラベルの漏れが多いもの）")
    ap.add_argument("--classifier", type=Path, help="ラベルの付いていない牌を外すのに使う分類モデル")
    ap.add_argument("--trusted-prefix", nargs="*", default=[], help="ラベルに漏れがないデータ（合成など）のファイル名の頭")
    ap.add_argument("--max-tile-prob", type=float, default=0.98)
    ap.add_argument("--haku-like-prob", type=float, default=0.5)
    ap.add_argument("--haku-like-saturation", type=float, default=0.3)
    ap.add_argument("--label-negatives", nargs="*", default=[],
                    help="元のデータセットのフォルダ:merge.py で付いたファイル名の頭:クラス名（例 data/roboflow/riichi_detection/train:s2_:0z）")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    interp, anchors, labels = evaluate.load(args.model)
    coco = json.loads((args.data / "labels.json").read_text())
    gts = {}
    for a in coco["annotations"]:
        gts.setdefault(a["image_id"], []).append(a)

    items = []
    n_det = n_rand = 0
    classifier = evaluate.Classifier(args.classifier) if args.classifier else None
    n_skip = 0
    for k, im in enumerate(coco["images"]):
        if any(im["file_name"].startswith(p) for p in args.skip_prefix):
            continue
        trusted = any(im["file_name"].startswith(p) for p in args.trusted_prefix)

        def looks_like_tile(x, y, w, h):
            if classifier is None or trusted:
                return False
            return classifier.probs(img, x, y, x + w, y + h).max() >= args.max_tile_prob

        def looks_like_haku(x, y, w, h):
            if classifier is None or not trusted:
                return False
            # 箱の中央の彩度（HSV の S）の平均。色のはっきりしたもの（牌の背など）は白に似ていない
            crop = np.asarray(img.convert("RGB").crop((x + w * 0.2, y + h * 0.2, x + w * 0.8, y + h * 0.8)), np.float32)
            mx, mn = crop.max(-1), crop.min(-1)
            saturation = float(np.mean((mx - mn) / np.maximum(mx, 1)))
            if saturation >= args.haku_like_saturation:
                return False
            return classifier.probs(img, x, y, x + w, y + h)[classifier.labels.index("5z")] >= args.haku_like_prob

        img = Image.open(args.data / "images" / im["file_name"])
        W, H = img.size
        gt = [(None, 1.0, a["bbox"][0] / W, a["bbox"][1] / H,
               (a["bbox"][0] + a["bbox"][2]) / W, (a["bbox"][1] + a["bbox"][3]) / H) for a in gts.get(im["id"], [])]
        dets = evaluate.detect(interp, anchors, labels, img, args.threshold)
        wrong = [d for d in dets if all(evaluate.iou(d, g) < args.max_iou for g in gt)]
        for d in wrong[: args.per_image]:
            bbox = [d[2] * W, d[3] * H, (d[4] - d[2]) * W, (d[5] - d[3]) * H]
            if looks_like_tile(*bbox) or looks_like_haku(*bbox):
                n_skip += 1
                continue
            items.append({"file": im["file_name"], "bbox": bbox, "source": "detector", "score": round(d[1], 3)})
            n_det += 1
        # 牌の無い所を、牌と同じくらいの大きさで切り抜く
        if gt:
            sizes = sorted(((g[4] - g[2]) * W, (g[5] - g[3]) * H) for g in gt)
            tw, th = sizes[len(sizes) // 2]
            count = int(args.random_per_image) + (rng.random() < args.random_per_image % 1)
            for _ in range(count * 10):
                if count == 0:
                    break
                s = rng.uniform(0.7, 1.3)
                w, h = tw * s, th * s
                if w >= W or h >= H:
                    break
                x, y = rng.uniform(0, W - w), rng.uniform(0, H - h)
                box = (None, 1.0, x / W, y / H, (x + w) / W, (y + h) / H)
                if all(evaluate.iou(box, g) < 0.05 for g in gt):
                    if looks_like_tile(x, y, w, h):
                        n_skip += 1
                        continue
                    items.append({"file": im["file_name"], "bbox": [x, y, w, h], "source": "random"})
                    n_rand += 1
                    count -= 1
        if k % 500 == 0:
            print(f"  {k}/{len(coco['images'])} images: 間違いの検出 {n_det}、背景 {n_rand}", flush=True)

    # 元のデータセットでラベルの付いた「牌ではないもの」（牌の背など）
    names = {im["file_name"] for im in coco["images"]}
    n_label = 0
    for spec in args.label_negatives:
        src, prefix, cls = spec.rsplit(":", 2)
        raw = json.loads((Path(src) / "_annotations.coco.json").read_text())
        ids = {c["id"] for c in raw["categories"] if c["name"] == cls}
        files = {im["id"]: prefix + Path(im["file_name"]).name for im in raw["images"]}
        for a in raw["annotations"]:
            if a["category_id"] in ids and files[a["image_id"]] in names and a["bbox"][2] > 1 and a["bbox"][3] > 1:
                items.append({"file": files[a["image_id"]], "bbox": a["bbox"], "source": f"label:{cls}"})
                n_label += 1

    args.out.write_text(json.dumps({"items": items}))
    if n_label:
        print(f"ラベルの付いた牌ではないもの: {n_label}")
    print(f"{args.out}: 間違いの検出 {n_det}、背景 {n_rand}（合計 {len(items)}）、牌・白らしいので外した {n_skip}")


if __name__ == "__main__":
    main()
