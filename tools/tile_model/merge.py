"""いくつかの COCO 形式のデータを、学習用（Model Maker の形式）に1つにまとめる。

入力にできる形式:
  - synth.py の出力（images/ と labels.json）
  - Roboflow の COCO 書き出し（各フォルダに _annotations.coco.json と画像）

クラス名は classes.normalize_label でアプリの牌の表記に変換する。変換できないクラス名があれば
一覧を出して止まる（--map で {"元の名前": "1m"} の JSON を渡すか、--drop で外す）。

使い方:
  python merge.py --out data/train --src data/synth_1 data/synth_2 data/roboflow/hust/train
  python merge.py --out data/val   --src data/synth_val data/roboflow/hust/valid
"""

import argparse
import json
import shutil
from pathlib import Path

import sys  # noqa: E402

# python -I で動かしても同じフォルダの classes.py を読めるようにする
sys.path.insert(0, str(Path(__file__).resolve().parent))
from classes import CLASSES, normalize_label


def load_coco(src: Path):
    if (src / "labels.json").exists():
        return json.loads((src / "labels.json").read_text()), src / "images"
    ann = src / "_annotations.coco.json"
    if ann.exists():
        return json.loads(ann.read_text()), src
    raise SystemExit(f"{src} に labels.json も _annotations.coco.json もありません")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--src", required=True, nargs="+", type=Path)
    ap.add_argument("--map", type=Path, help='クラス名の対応表 JSON {"元の名前": "1m", "外す名前": null}')
    ap.add_argument("--drop", nargs="*", default=[], help="外すクラス名")
    args = ap.parse_args()

    manual = json.loads(args.map.read_text()) if args.map else {}
    (args.out / "images").mkdir(parents=True, exist_ok=True)
    cat_id = {c: i + 1 for i, c in enumerate(CLASSES)}
    images, annotations = [], []
    unknown = {}

    for si, src in enumerate(args.src):
        coco, img_dir = load_coco(src)
        counts = {}
        for a in coco["annotations"]:
            counts[a["category_id"]] = counts.get(a["category_id"], 0) + 1
        mapping = {}
        for c in coco["categories"]:
            name = c["name"]
            if name in manual:
                mapping[c["id"]] = manual[name]
            elif name in args.drop or name == "background":
                mapping[c["id"]] = None
            else:
                lab = normalize_label(name)
                mapping[c["id"]] = lab
                if lab is None and counts.get(c["id"], 0) > 0:
                    unknown.setdefault(str(src), []).append(f"{name}（{counts[c['id']]}個）")
        print(f"[{src}] " + ", ".join(f"{c['name']}→{mapping[c['id']]}" for c in coco["categories"]
                                         if counts.get(c["id"], 0) > 0))
        if unknown:
            continue

        id_map = {}
        for im in coco["images"]:
            new_id = len(images) + 1
            id_map[im["id"]] = new_id
            name = f"s{si}_{Path(im['file_name']).name}"
            shutil.copy(img_dir / im["file_name"], args.out / "images" / name)
            images.append({"id": new_id, "file_name": name, "width": im.get("width"), "height": im.get("height")})
        for a in coco["annotations"]:
            lab = mapping.get(a["category_id"])
            if lab is None or a["image_id"] not in id_map:
                continue
            x, y, w, h = a["bbox"]
            if w <= 1 or h <= 1:
                continue
            annotations.append({
                "id": len(annotations) + 1, "image_id": id_map[a["image_id"]],
                "category_id": cat_id[lab], "bbox": [x, y, w, h], "area": w * h, "iscrowd": 0,
            })

    if unknown:
        for src, names in unknown.items():
            print(f"変換できないクラス名 [{src}]: {', '.join(names)}")
        raise SystemExit("--map で対応を指定するか、--drop で外してください")

    categories = [{"id": 0, "name": "background"}] + [{"id": i + 1, "name": c} for i, c in enumerate(CLASSES)]
    (args.out / "labels.json").write_text(json.dumps(
        {"images": images, "annotations": annotations, "categories": categories}))
    per = {}
    for a in annotations:
        per[CLASSES[a["category_id"] - 1]] = per.get(CLASSES[a["category_id"] - 1], 0) + 1
    print(f"{args.out}: {len(images)} images, {len(annotations)} boxes")
    print("クラスごとの数:", {c: per.get(c, 0) for c in CLASSES})


if __name__ == "__main__":
    main()
