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

使い方:
  python mine_negatives.py --model out --data data/train --out data/train/negatives.json \
      --classifier out_cls_first --trusted-prefix s0_ s1_ s2_ --skip-prefix s4_
  （out_cls_first は「牌ではない」なしで先に学習した分類モデル）
"""

import argparse
import json
import random
import sys
from pathlib import Path

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

        img = Image.open(args.data / "images" / im["file_name"])
        W, H = img.size
        gt = [(None, 1.0, a["bbox"][0] / W, a["bbox"][1] / H,
               (a["bbox"][0] + a["bbox"][2]) / W, (a["bbox"][1] + a["bbox"][3]) / H) for a in gts.get(im["id"], [])]
        dets = evaluate.detect(interp, anchors, labels, img, args.threshold)
        wrong = [d for d in dets if all(evaluate.iou(d, g) < args.max_iou for g in gt)]
        for d in wrong[: args.per_image]:
            bbox = [d[2] * W, d[3] * H, (d[4] - d[2]) * W, (d[5] - d[3]) * H]
            if looks_like_tile(*bbox):
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

    args.out.write_text(json.dumps({"items": items}))
    print(f"{args.out}: 間違いの検出 {n_det}、背景 {n_rand}（合計 {len(items)}）、牌らしいので外した {n_skip}")


if __name__ == "__main__":
    main()
