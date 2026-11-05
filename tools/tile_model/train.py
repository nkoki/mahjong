"""MediaPipe Model Maker（Apache-2.0）で牌の検出モデルを学習し、TFLite に書き出す。

使い方:
  python train.py --train data/train --val data/val --out out --epochs 40

出力（--out の中）:
  tile_detector.tflite   アプリに入れるモデル（assets/models/ にコピーする）
  tile_anchors.bin       箱の位置の基準（アンカー）。float32 × 4（y中心, x中心, 高さ, 幅）× アンカー数
  tile_labels.txt        クラス名（モデルの出力の順番）
  metadata.json          Model Maker が書き出すモデルの説明
  eval.json              確認用データでの精度（COCO 指標）
"""

import argparse
import json
import shutil
import struct
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--train", required=True, type=Path)
    ap.add_argument("--val", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--cache", type=Path, default=Path("cache"))
    ap.add_argument("--model", default="MOBILENET_MULTI_AVG_I384",
                    choices=["MOBILENET_V2", "MOBILENET_V2_I320", "MOBILENET_MULTI_AVG", "MOBILENET_MULTI_AVG_I384"])
    ap.add_argument("--epochs", type=int, default=40)
    ap.add_argument("--batch", type=int, default=16)
    ap.add_argument("--lr", type=float, default=0.3)
    ap.add_argument("--max-images", type=int, default=None, help="試しに動かすときの画像数の上限")
    ap.add_argument("--fp16", action="store_true", help="float16 で書き出す（ファイルが半分の大きさになる）")
    args = ap.parse_args()

    import tensorflow as tf
    from mediapipe_model_maker import object_detector, quantization

    args.out.mkdir(parents=True, exist_ok=True)
    train = object_detector.Dataset.from_coco_folder(
        str(args.train), cache_dir=str(args.cache / "train"), max_num_images=args.max_images)
    val = object_detector.Dataset.from_coco_folder(
        str(args.val), cache_dir=str(args.cache / "val"),
        max_num_images=args.max_images // 4 if args.max_images else None)
    print(f"train: {train.size} images, val: {val.size} images, labels: {train.label_names}")

    hparams = object_detector.HParams(
        export_dir=str(args.out / "export"),
        epochs=args.epochs,
        batch_size=args.batch,
        learning_rate=args.lr,
    )
    options = object_detector.ObjectDetectorOptions(
        supported_model=getattr(object_detector.SupportedModels, args.model),
        hparams=hparams,
    )
    model = object_detector.ObjectDetector.create(train_data=train, validation_data=val, options=options)

    loss, coco = model.evaluate(val, batch_size=args.batch)
    print("validation loss:", loss)
    print("COCO metrics:", coco)
    with open(args.out / "eval.json", "w") as f:
        json.dump({"loss": [float(v) for v in loss], "coco": {k: float(v) for k, v in coco.items()},
                   "model": args.model, "epochs": args.epochs, "train_images": train.size,
                   "val_images": val.size}, f, indent=2)

    qconf = quantization.QuantizationConfig.for_float16() if args.fp16 else None
    model.export_model("tile_detector.tflite", quantization_config=qconf)
    export = args.out / "export"
    shutil.copy(export / "tile_detector.tflite", args.out / "tile_detector.tflite")
    shutil.copy(export / "metadata.json", args.out / "metadata.json")

    # アンカーとクラス名を、アプリで読みやすい形で書き出す
    meta = json.loads((export / "metadata.json").read_text())
    anchors = find_anchors(meta)
    with open(args.out / "tile_anchors.bin", "wb") as f:
        for a in anchors:
            f.write(struct.pack("<4f", a["y_center"], a["x_center"], a["height"], a["width"]))
    labels = [n for n in train.label_names if n != "background"]
    (args.out / "tile_labels.txt").write_text("\n".join(labels) + "\n")
    print(f"anchors: {len(anchors)}, labels: {len(labels)}")

    interp = tf.lite.Interpreter(model_path=str(args.out / "tile_detector.tflite"))
    print("inputs:", [(d["name"], d["shape"], d["dtype"]) for d in interp.get_input_details()])
    print("outputs:", [(d["name"], d["shape"], d["dtype"]) for d in interp.get_output_details()])


def find_anchors(meta):
    """metadata.json から固定アンカーの一覧を取り出す"""
    found = []

    def walk(o):
        if isinstance(o, dict):
            if "anchors" in o and isinstance(o["anchors"], list) and o["anchors"] and "x_center" in o["anchors"][0]:
                found.append(o["anchors"])
                return
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)

    walk(meta)
    if not found:
        raise RuntimeError("metadata.json にアンカーが見つかりません")
    return [{k: float(a.get(k, 0.0)) for k in ("x_center", "y_center", "width", "height")} for a in found[0]]


if __name__ == "__main__":
    main()
