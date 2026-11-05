"""牌を1枚ずつ見分ける分類モデルを学習し、TFLite に書き出す。

検出モデル（train.py）が見つけた牌を1枚ずつ切り抜き、大きくしてから種類を見分け直すためのモデル。
萬子の漢数字（六と八など）のように、写真全体を縮めると潰れてしまう細かい違いを見分けやすくする。

学習データは merge.py の出力（labels.json と images/）の箱から切り抜いて作る。
もとにする学習済みモデルは Keras の MobileNetV3-Small（ImageNet、Apache-2.0）。

使い方:
  python train_classifier.py --train data/train --val data/val --out out_cls --epochs 12

出力（--out の中）:
  tile_classifier.tflite         アプリに入れるモデル（assets/models/ にコピーする）
                                 入力: float32 [1, 128, 96, 3]（RGB、0〜255）  出力: float32 [1, 37]（確率）
  tile_classifier_labels.txt     クラス名（出力の順番）
  eval.json                      確認用データでの正解率
"""

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

# python -I で動かしても同じフォルダのモジュールを読めるようにする
sys.path.insert(0, str(Path(__file__).resolve().parent))
from classes import CLASSES  # noqa: E402
from tile_crop import INPUT_H, INPUT_W, LANDSCAPE_RATIO, MARGIN, classifier_input  # noqa: E402

# 学習用の切り抜き: 箱を上下左右に CONTEXT ずつ広げて切り抜き、ずらし・拡大縮小はあとで行う
CONTEXT = 0.25
CTX_H, CTX_W = 160, 120


def load_boxes(folder: Path):
    coco = json.loads((folder / "labels.json").read_text())
    cats = {c["id"]: c["name"] for c in coco["categories"]}
    by_image = {}
    for a in coco["annotations"]:
        by_image.setdefault(a["image_id"], []).append(a)
    return coco["images"], cats, by_image


def extract_train(folder: Path, max_images=None):
    """学習用: 箱のまわりも含めて切り抜く（あとでずらして使う）"""
    images, cats, by_image = load_boxes(folder)
    images = images[:max_images] if max_images else images
    xs, ys = [], []
    for n, im in enumerate(images):
        anns = by_image.get(im["id"], [])
        if not anns:
            continue
        img = Image.open(folder / "images" / im["file_name"]).convert("RGB")
        for a in anns:
            x, y, w, h = a["bbox"]
            crop = img.crop((round(x - w * CONTEXT), round(y - h * CONTEXT),
                             round(x + w * (1 + CONTEXT)), round(y + h * (1 + CONTEXT))))
            if w > h * LANDSCAPE_RATIO:
                crop = crop.transpose(Image.Transpose.ROTATE_270)
            xs.append(np.asarray(crop.resize((CTX_W, CTX_H), Image.BOX), np.uint8))
            ys.append(CLASSES.index(cats[a["category_id"]]))
        if n % 500 == 0:
            print(f"  {folder.name}: {n}/{len(images)} images, {len(xs)} tiles", flush=True)
    return np.stack(xs), np.array(ys, np.int32)


def extract_val(folder: Path, max_images=None):
    """確認用: アプリと同じ切り抜き方（tile_crop.classifier_input）"""
    images, cats, by_image = load_boxes(folder)
    images = images[-max_images:] if max_images else images
    xs, ys, real = [], [], []
    for im in images:
        anns = by_image.get(im["id"], [])
        if not anns:
            continue
        img = Image.open(folder / "images" / im["file_name"]).convert("RGB")
        for a in anns:
            x, y, w, h = a["bbox"]
            xs.append(np.asarray(classifier_input(img, x, y, x + w, y + h), np.uint8))
            ys.append(CLASSES.index(cats[a["category_id"]]))
            real.append(not im["file_name"].startswith("s0_"))  # merge.py で最初に渡したもの（合成）以外
    return np.stack(xs), np.array(ys, np.int32), np.array(real)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--train", required=True, type=Path)
    ap.add_argument("--val", required=True, type=Path,
                    help="merge.py の出力。最初の --src を合成データにしておくと、実写だけの正解率も出す")
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--epochs", type=int, default=12)
    ap.add_argument("--batch", type=int, default=64)
    ap.add_argument("--lr", type=float, default=2e-3)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--max-images", type=int, default=None, help="試しに動かすときの画像数の上限")
    args = ap.parse_args()

    import tensorflow as tf
    tf.keras.utils.set_random_seed(args.seed)
    args.out.mkdir(parents=True, exist_ok=True)

    t0 = time.time()
    x_train, y_train = extract_train(args.train, args.max_images)
    x_val, y_val, val_real = extract_val(args.val, args.max_images // 4 if args.max_images else None)
    print(f"train: {len(y_train)} tiles, val: {len(y_val)} tiles（実写 {val_real.sum()}）"
          f"  切り抜き {time.time() - t0:.0f} 秒", flush=True)

    # 学習用の切り抜きの中で、アプリの切り抜き（箱を MARGIN ずつ広げた範囲）の大きさの半分（割合）
    half = (0.5 + MARGIN) / (1 + 2 * CONTEXT)

    def augment(img, label):
        """バッチごとに、箱のずらし・拡大縮小と、明るさ・コントラスト・鮮やかさの変化をつける"""
        img = tf.cast(img, tf.float32)
        b = tf.shape(img)[0]
        u = lambda lo, hi: tf.random.uniform([b], lo, hi)
        cy, cx = 0.5 + u(-0.03, 0.03), 0.5 + u(-0.03, 0.03)
        s = u(0.9, 1.1)
        hy, hx = half * s * u(0.95, 1.05), half * s * u(0.95, 1.05)
        boxes = tf.stack([cy - hy, cx - hx, cy + hy, cx + hx], 1)
        img = tf.image.crop_and_resize(img, boxes, tf.range(b), [INPUT_H, INPUT_W])
        r = lambda lo, hi: tf.random.uniform([b, 1, 1, 1], lo, hi)
        img = img + r(-30, 30)
        mean = tf.reduce_mean(img, [1, 2, 3], keepdims=True)
        img = (img - mean) * r(0.75, 1.25) + mean
        gray = tf.reduce_mean(img, 3, keepdims=True)
        img = gray + (img - gray) * r(0.7, 1.3)
        return tf.clip_by_value(img, 0, 255), label

    # 画像は numpy のまま持ち、並べ替えは番号で行う（全部を Dataset に入れるとメモリが足りなくなる）
    def gather(idx):
        return x_train[idx], y_train[idx]

    def load_batch(idx):
        x, y = tf.numpy_function(gather, [idx], [tf.uint8, tf.int32])
        x.set_shape([None, CTX_H, CTX_W, 3])
        y.set_shape([None])
        return x, y

    train_ds = (tf.data.Dataset.from_tensor_slices(np.arange(len(y_train)))
                .shuffle(len(y_train), seed=args.seed, reshuffle_each_iteration=True)
                .batch(args.batch)
                .map(load_batch, num_parallel_calls=2)
                .map(augment, num_parallel_calls=2)
                .prefetch(2))

    def gather_val(idx):
        return x_val[idx].astype(np.float32), y_val[idx]

    def load_val(idx):
        x, y = tf.numpy_function(gather_val, [idx], [tf.float32, tf.int32])
        x.set_shape([None, INPUT_H, INPUT_W, 3])
        y.set_shape([None])
        return x, y

    val_ds = tf.data.Dataset.from_tensor_slices(np.arange(len(y_val))).batch(256).map(load_val)

    base = tf.keras.applications.MobileNetV3Small(
        input_shape=(INPUT_H, INPUT_W, 3), include_top=False, weights="imagenet", pooling="avg")
    inputs = tf.keras.Input((INPUT_H, INPUT_W, 3))
    x = base(inputs)
    x = tf.keras.layers.Dropout(0.2)(x)
    outputs = tf.keras.layers.Dense(len(CLASSES), activation="softmax")(x)
    model = tf.keras.Model(inputs, outputs)

    steps = args.epochs * ((len(y_train) + args.batch - 1) // args.batch)
    schedule = tf.keras.optimizers.schedules.CosineDecay(args.lr, steps)
    model.compile(optimizer=tf.keras.optimizers.Adam(schedule),
                  loss=tf.keras.losses.SparseCategoricalCrossentropy(),
                  metrics=["accuracy"])
    model.fit(train_ds, validation_data=val_ds, epochs=args.epochs, verbose=2)

    pred = model.predict(val_ds, verbose=0).argmax(1)
    ok = pred == y_val
    per_class = {c: round(float(ok[y_val == i].mean()), 4) for i, c in enumerate(CLASSES) if (y_val == i).any()}
    confusions = {}
    for t, p in zip(y_val[~ok & val_real], pred[~ok & val_real]):
        k = f"{CLASSES[t]}→{CLASSES[p]}"
        confusions[k] = confusions.get(k, 0) + 1
    result = {
        "val_accuracy": round(float(ok.mean()), 4),
        "val_accuracy_real": round(float(ok[val_real].mean()), 4) if val_real.any() else None,
        "val_accuracy_synth": round(float(ok[~val_real].mean()), 4) if (~val_real).any() else None,
        "per_class": per_class,
        "top_confusions_real": sorted(confusions.items(), key=lambda kv: -kv[1])[:12],
        "train_tiles": int(len(y_train)), "val_tiles": int(len(y_val)), "epochs": args.epochs,
        "input": [INPUT_H, INPUT_W],
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    (args.out / "eval.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    (args.out / "tile_classifier.tflite").write_bytes(converter.convert())
    (args.out / "tile_classifier_labels.txt").write_text("\n".join(CLASSES) + "\n")

    # 書き出したモデルが Keras と同じ答えを出すか確かめる
    interp = tf.lite.Interpreter(model_path=str(args.out / "tile_classifier.tflite"))
    interp.allocate_tensors()
    inp, out = interp.get_input_details()[0], interp.get_output_details()[0]
    print("input:", inp["shape"], inp["dtype"], " output:", out["shape"], out["dtype"])
    same = 0
    n = min(300, len(y_val))
    for i in range(n):
        interp.set_tensor(inp["index"], x_val[i:i + 1].astype(np.float32))
        interp.invoke()
        same += int(interp.get_tensor(out["index"])[0].argmax() == pred[i])
    print(f"TFLite と Keras の答えが同じ: {same}/{n}")


if __name__ == "__main__":
    main()
