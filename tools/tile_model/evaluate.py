"""書き出した TFLite モデルを、アプリと同じ後処理で確認用データに当てて、読み取りの精度を測る。

アプリ（lib/features/camera/tile_detection.dart・tflite_tile_recognizer.dart）と同じく:
  縦横比を保って正方形に縮める（右・下は余白）→ アンカーで箱を求める → NMS（種類に関係なく）

使い方:
  python evaluate.py --model out --data data/val [--save-preview preview.jpg]
  python evaluate.py --model out --data data/val_real --two-pass --hand-rows --per-class

  --two-pass   アプリと同じく、牌の写っている範囲を切り抜いてもう一度読み取る（2回目の読み取り）
  --hand-rows  写真の中の牌の列を1列ずつ取り出し、14枚の手牌を撮ったときと同じくらいの大きさで
               写した画像を作って測る（実写の確認用データは1枚に牌が約30枚あり、手牌の写真より牌が小さいため）
  --per-class  牌の種類ごとの精度と、多い取り違えを出す
  --classifier 分類モデル（train_classifier.py の出力のフォルダ）で、見つけた牌の種類を決め直す（アプリと同じ）

出力:
  牌ごとの精度（正しい位置で見つけた牌のうち種類も合っていた割合）・見落とし・余計な検出、
  1枚の写真の牌が全部正しく読めた割合
"""

import argparse
import json
import math
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image


class Classifier:
    """牌を1枚ずつ見分ける分類モデル（アプリの tile_classifier.dart と同じ使い方）"""

    def __init__(self, model_dir: Path):
        import sys
        import tensorflow as tf
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from tile_crop import classifier_input
        self.classifier_input = classifier_input
        self.interp = tf.lite.Interpreter(model_path=str(model_dir / "tile_classifier.tflite"))
        self.interp.allocate_tensors()
        self.labels = [l.strip() for l in (model_dir / "tile_classifier_labels.txt").read_text().splitlines()
                       if l.strip()]

    def probs(self, image: Image.Image, left, top, right, bottom):
        x = np.asarray(self.classifier_input(image, left, top, right, bottom), np.float32)[None]
        inp, out = self.interp.get_input_details()[0], self.interp.get_output_details()[0]
        self.interp.set_tensor(inp["index"], x)
        self.interp.invoke()
        return self.interp.get_tensor(out["index"])[0]

    def relabel(self, image: Image.Image, dets):
        """見つけた牌（座標は割合）の種類を、分類モデルの答えに置き換える"""
        W, H = image.size
        result = []
        for d in dets:
            p = self.probs(image, d[2] * W, d[3] * H, d[4] * W, d[5] * H)
            result.append((self.labels[int(p.argmax())],) + tuple(d[1:]))
        return result


def load(model_dir: Path):
    import tensorflow as tf
    interp = tf.lite.Interpreter(model_path=str(model_dir / "tile_detector.tflite"))
    interp.allocate_tensors()
    anchors = np.fromfile(model_dir / "tile_anchors.bin", dtype="<f4").reshape(-1, 4)
    labels = [l.strip() for l in (model_dir / "tile_labels.txt").read_text().splitlines() if l.strip()]
    return interp, anchors, labels


def detect(interp, anchors, labels, image: Image.Image, threshold=0.3, iou_th=0.45):
    inp = interp.get_input_details()[0]
    size = inp["shape"][1]
    w, h = image.size
    scale = size / max(w, h)
    rw, rh = max(1, round(w * scale)), max(1, round(h * scale))
    arr = np.zeros((size, size, 3), np.float32)
    arr[:rh, :rw] = (np.asarray(image.convert("RGB").resize((rw, rh), Image.BOX), np.float32) - 127.5) / 127.5
    interp.set_tensor(inp["index"], arr[None])
    interp.invoke()
    outs = [interp.get_tensor(o["index"])[0] for o in interp.get_output_details()]
    boxes = next(o for o in outs if o.shape[-1] == 4)
    scores = next(o for o in outs if o.shape[-1] != 4)
    offset = scores.shape[1] - len(labels)
    cls = scores[:, offset:]
    best = cls.argmax(1)
    best_s = cls.max(1)
    keep = np.where(best_s > threshold)[0]
    dets = []
    for i in keep:
        ay, ax, ah, aw = anchors[i]
        yc = boxes[i, 0] * ah + ay
        xc = boxes[i, 1] * aw + ax
        bh = math.exp(boxes[i, 2]) * ah
        bw = math.exp(boxes[i, 3]) * aw
        sx, sy = size / rw, size / rh
        dets.append((labels[best[i]], float(best_s[i]),
                     (xc - bw / 2) * sx, (yc - bh / 2) * sy, (xc + bw / 2) * sx, (yc + bh / 2) * sy))
    dets.sort(key=lambda d: -d[1])
    kept = []
    for d in dets:
        if all(iou(d, k) < iou_th for k in kept):
            kept.append(d)
        if len(kept) >= 40:
            break
    return kept


def iou(a, b):
    w = min(a[4], b[4]) - max(a[2], b[2])
    h = min(a[5], b[5]) - max(a[3], b[3])
    if w <= 0 or h <= 0:
        return 0.0
    inter = w * h
    area = lambda d: (d[4] - d[2]) * (d[5] - d[3])
    return inter / (area(a) + area(b) - inter)


def crop_region(dets, margin=0.6, max_area_ratio=0.5):
    """アプリの cropRegion と同じ。2回目に読み取る範囲（割合 left, top, right, bottom）か None"""
    if not dets:
        return None
    sizes = sorted(max(d[4] - d[2], d[5] - d[3]) for d in dets)
    pad = sizes[len(sizes) // 2] * margin
    l = max(0.0, min(d[2] for d in dets) - pad)
    t = max(0.0, min(d[3] for d in dets) - pad)
    r = min(1.0, max(d[4] for d in dets) + pad)
    b = min(1.0, max(d[5] for d in dets) + pad)
    if (r - l) * (b - t) > max_area_ratio:
        return None
    return l, t, r, b


def detect_two_pass(interp, anchors, labels, image: Image.Image, threshold=0.3):
    """アプリ（tflite_tile_recognizer.dart の _run）と同じ2回の読み取り"""
    dets = detect(interp, anchors, labels, image, threshold)
    region = crop_region(dets)
    if region is None:
        return dets
    W, H = image.size
    x, y = math.floor(region[0] * W), math.floor(region[1] * H)
    w = max(1, math.ceil((region[2] - region[0]) * W))
    h = max(1, math.ceil((region[3] - region[1]) * H))
    again = detect(interp, anchors, labels, image.crop((x, y, x + w, y + h)), threshold)
    if len(again) < len(dets) * 0.8:
        return dets
    cx, cy, cw, ch = x / W, y / H, w / W, h / H
    return [(d[0], d[1], cx + d[2] * cw, cy + d[3] * ch, cx + d[4] * cw, cy + d[5] * ch) for d in again]


def hand_rows(image: Image.Image, gt, hand_size=14):
    """写真の中の牌の列（5枚以上）を1列ずつ取り出し、手牌 hand_size 枚が写真の幅いっぱいに
    写るときと同じ大きさになるように、まわりを写真の色で埋めた画像を作る。

    gt は (牌, 1, left, top, right, bottom)（割合）。(画像, その列の gt) を順に返す
    """
    W, H = image.size
    if not gt:
        return
    unit = sorted(min((g[4] - g[2]) * W, (g[5] - g[3]) * H) for g in gt)[len(gt) // 2]
    rows = []
    for g in sorted(gt, key=lambda g: (g[3] + g[5]) / 2 * H):
        cy = (g[3] + g[5]) / 2 * H
        if rows and abs(cy - sum((r[3] + r[5]) / 2 * H for r in rows[-1]) / len(rows[-1])) < unit * 0.8:
            rows[-1].append(g)
        else:
            rows.append([g])
    fill = tuple(int(v) for v in np.median(np.asarray(image.convert("RGB")).reshape(-1, 3), axis=0))
    for row in rows:
        if len(row) < 5:
            continue
        l = min(g[2] for g in row) * W
        t = min(g[3] for g in row) * H
        r = max(g[4] for g in row) * W
        b = max(g[5] for g in row) * H
        tile_w = sorted((g[4] - g[2]) * W for g in row)[len(row) // 2]
        # 列だけを切り抜く（上下・左右に牌の 0.3 枚分の余白）。ほかの列は写さない
        pad = tile_w * 0.3
        box = (max(0, int(l - pad)), max(0, int(t - pad)), min(W, int(r + pad)), min(H, int(b + pad)))
        crop = image.convert("RGB").crop(box)
        cw = max(crop.width, int(tile_w * (hand_size + 1)))
        ch = max(crop.height, int(cw * 3 / 4))
        canvas = Image.new("RGB", (cw, ch), fill)
        ox, oy = (cw - crop.width) // 2, (ch - crop.height) // 2
        canvas.paste(crop, (ox, oy))
        row_gt = [(g[0], 1.0, (g[2] * W - box[0] + ox) / cw, (g[3] * H - box[1] + oy) / ch,
                   (g[4] * W - box[0] + ox) / cw, (g[5] * H - box[1] + oy) / ch) for g in row]
        yield canvas, row_gt


def samples(args, coco, cats, gts):
    images = coco["images"][: args.max_images] if args.max_images else coco["images"]
    for im in images:
        img = Image.open(args.data / "images" / im["file_name"])
        W, H = img.size
        gt = [(cats[a["category_id"]], 1.0, a["bbox"][0] / W, a["bbox"][1] / H,
               (a["bbox"][0] + a["bbox"][2]) / W, (a["bbox"][1] + a["bbox"][3]) / H)
              for a in gts.get(im["id"], [])]
        if args.hand_rows:
            yield from hand_rows(img, gt)
        else:
            yield img, gt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True, type=Path)
    ap.add_argument("--data", required=True, type=Path)
    ap.add_argument("--threshold", type=float, default=0.3)
    ap.add_argument("--max-images", type=int, default=None)
    ap.add_argument("--save-preview", type=Path)
    ap.add_argument("--two-pass", action="store_true", help="アプリと同じく2回目の読み取りもする")
    ap.add_argument("--hand-rows", action="store_true", help="牌の列を1列ずつ手牌の写真のようにして測る")
    ap.add_argument("--per-class", action="store_true", help="牌の種類ごとの精度と多い取り違えを出す")
    ap.add_argument("--classifier", type=Path, help="分類モデルのフォルダ（見つけた牌の種類を決め直す）")
    ap.add_argument("--dump-fixture", type=Path,
                    help="アプリのテスト用に、確信度の高いアンカーの生の出力と期待する箱を JSON に書く")
    args = ap.parse_args()

    interp, anchors, labels = load(args.model)
    if args.dump_fixture:
        dump_fixture(interp, anchors, labels, args.data, args.dump_fixture)
        return
    coco = json.loads((args.data / "labels.json").read_text())
    cats = {c["id"]: c["name"] for c in coco["categories"]}
    gts = {}
    for a in coco["annotations"]:
        gts.setdefault(a["image_id"], []).append(a)
    found = correct = missed = extra = 0
    perfect = count = 0
    previews = []
    per_total, per_ok, confusions = Counter(), Counter(), Counter()
    classifier = Classifier(args.classifier) if args.classifier else None
    for img, gt in samples(args, coco, cats, gts):
        count += 1
        W, H = img.size
        dets = (detect_two_pass if args.two_pass else detect)(interp, anchors, labels, img, args.threshold)
        if classifier:
            dets = classifier.relabel(img, dets)
        used = set()
        ok_all = True
        for g in gt:
            best, bi = 0.0, -1
            for i, d in enumerate(dets):
                if i in used:
                    continue
                v = iou(g, d)
                if v > best:
                    best, bi = v, i
            per_total[g[0]] += 1
            if best >= 0.5:
                used.add(bi)
                found += 1
                if dets[bi][0] == g[0]:
                    correct += 1
                    per_ok[g[0]] += 1
                else:
                    ok_all = False
                    confusions[(g[0], dets[bi][0])] += 1
            else:
                missed += 1
                ok_all = False
                confusions[(g[0], "見落とし")] += 1
        extra += len(dets) - len(used)
        if len(dets) != len(used):
            ok_all = False
        perfect += ok_all
        if args.save_preview and len(previews) < 6:
            from PIL import ImageDraw
            p = img.convert("RGB").copy()
            dr = ImageDraw.Draw(p)
            for d in dets:
                dr.rectangle([d[2] * W, d[3] * H, d[4] * W, d[5] * H], outline=(255, 0, 0))
                dr.text((d[2] * W, d[3] * H - 10), d[0], fill=(255, 0, 0))
            previews.append(p.resize((640, int(640 * H / W))))
    total = found + missed
    result = {
        "images": count,
        "tiles": total,
        "detected_ratio": round(found / max(1, total), 4),
        "class_accuracy_of_detected": round(correct / max(1, found), 4),
        "tile_accuracy": round(correct / max(1, total), 4),
        "extra_detections_per_image": round(extra / max(1, count), 3),
        "all_tiles_correct_ratio": round(perfect / max(1, count), 4),
    }
    if args.per_class:
        result["per_class_accuracy"] = {c: round(per_ok[c] / per_total[c], 3) for c in labels if per_total[c]}
        result["top_confusions"] = [f"{a}→{b}: {n}" for (a, b), n in confusions.most_common(12)]
    print(json.dumps(result, indent=2))
    if previews:
        canvas = Image.new("RGB", (640, sum(p.size[1] for p in previews)))
        y = 0
        for p in previews:
            canvas.paste(p, (0, y))
            y += p.size[1]
        canvas.save(args.save_preview)


def dump_fixture(interp, anchors, labels, data: Path, out: Path, count=30):
    """アプリの decodeDetections と同じ計算になっているかを確かめるためのデータ"""
    coco = json.loads((data / "labels.json").read_text())
    img = Image.open(data / "images" / coco["images"][0]["file_name"])
    detect(interp, anchors, labels, img, threshold=1.1)  # 実行だけ
    outs = [interp.get_tensor(o["index"])[0] for o in interp.get_output_details()]
    boxes = next(o for o in outs if o.shape[-1] == 4)
    scores = next(o for o in outs if o.shape[-1] != 4)
    offset = scores.shape[1] - len(labels)
    top = np.argsort(-scores[:, offset:].max(1))[:count]
    expected = []
    for i in top:
        ay, ax, ah, aw = anchors[i]
        yc = boxes[i, 0] * ah + ay
        xc = boxes[i, 1] * aw + ax
        bh = math.exp(boxes[i, 2]) * ah
        bw = math.exp(boxes[i, 3]) * aw
        c = int(scores[i, offset:].argmax())
        expected.append({"tile": labels[c], "score": float(scores[i, offset + c]),
                         "left": xc - bw / 2, "top": yc - bh / 2, "right": xc + bw / 2, "bottom": yc + bh / 2})
    out.write_text(json.dumps({
        "labels": labels,
        "raw_boxes": [float(v) for i in top for v in boxes[i]],
        "raw_scores": [float(v) for i in top for v in scores[i]],
        "anchors": [float(v) for i in top for v in anchors[i]],
        "expected": expected,
    }))
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
