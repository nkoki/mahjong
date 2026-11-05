"""書き出した TFLite モデルを、アプリと同じ後処理で確認用データに当てて、読み取りの精度を測る。

アプリ（lib/features/camera/tile_detection.dart・tflite_tile_recognizer.dart）と同じく:
  縦横比を保って正方形に縮める（右・下は余白）→ アンカーで箱を求める → NMS（種類に関係なく）

使い方:
  python evaluate.py --model out --data data/val [--save-preview preview.jpg]

出力:
  牌ごとの精度（正しい位置で見つけた牌のうち種類も合っていた割合）・見落とし・余計な検出、
  1枚の写真の牌が全部正しく読めた割合
"""

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True, type=Path)
    ap.add_argument("--data", required=True, type=Path)
    ap.add_argument("--threshold", type=float, default=0.3)
    ap.add_argument("--max-images", type=int, default=None)
    ap.add_argument("--save-preview", type=Path)
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
    images = coco["images"][: args.max_images] if args.max_images else coco["images"]

    found = correct = missed = extra = 0
    perfect = 0
    previews = []
    for im in images:
        img = Image.open(args.data / "images" / im["file_name"])
        W, H = img.size
        dets = detect(interp, anchors, labels, img, args.threshold)
        gt = [(cats[a["category_id"]], 1.0, a["bbox"][0] / W, a["bbox"][1] / H,
               (a["bbox"][0] + a["bbox"][2]) / W, (a["bbox"][1] + a["bbox"][3]) / H)
              for a in gts.get(im["id"], [])]
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
            if best >= 0.5:
                used.add(bi)
                found += 1
                if dets[bi][0] == g[0]:
                    correct += 1
                else:
                    ok_all = False
            else:
                missed += 1
                ok_all = False
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
        "images": len(images),
        "tiles": total,
        "detected_ratio": round(found / max(1, total), 4),
        "class_accuracy_of_detected": round(correct / max(1, found), 4),
        "tile_accuracy": round(correct / max(1, total), 4),
        "extra_detections_per_image": round(extra / max(1, len(images)), 3),
        "all_tiles_correct_ratio": round(perfect / max(1, len(images)), 4),
    }
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
