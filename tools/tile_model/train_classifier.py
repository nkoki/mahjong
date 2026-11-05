"""牌を1枚ずつ見分ける分類モデルを学習し、TFLite に書き出す。

検出モデル（train.py）が見つけた牌を1枚ずつ切り抜き、大きくしてから種類を見分け直すためのモデル。
萬子の漢数字（六と八など）のように、写真全体を縮めると潰れてしまう細かい違いを見分けやすくする。

学習データは merge.py の出力（labels.json と images/）の箱から切り抜いて作る。
もとにする学習済みモデルは Keras の MobileNetV3-Small（ImageNet、Apache-2.0）。

「牌ではない（bg）」のクラスも学習する（mine_negatives.py で集めた、検出モデルが間違えて見つけたものと背景）。
アプリは、分類モデルが「牌ではない」と答えた検出を捨てる（余計な検出を減らす）。

使い方:
  python train_classifier.py --train data/train --val data/val --out out_cls --epochs 8 \
      --negatives data/train/negatives.json --val-negatives data/val/negatives.json --plain-negatives 1500

出力（--out の中）:
  tile_classifier.tflite         アプリに入れるモデル（assets/models/ にコピーする）
                                 入力: float32 [1, 128, 96, 3]（RGB、0〜255）  出力: float32 [1, 38]（確率）
  tile_classifier_labels.txt     クラス名（出力の順番。37種類の牌と、最後に bg＝牌ではない）
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

# 「牌ではない」（検出モデルが間違えて見つけたもの・背景）のクラス。アプリはこの答えの検出を捨てる
NOT_A_TILE = "bg"
LABELS = CLASSES + [NOT_A_TILE]

# 学習用の切り抜き: 箱を上下左右に CONTEXT ずつ広げて切り抜き、ずらし・拡大縮小はあとで行う
CONTEXT = 0.25
CTX_H, CTX_W = 160, 120


def load_items(folder: Path, negatives=None, max_images=None, last=False):
    """切り抜く箱の一覧 [(ファイル名, (x, y, w, h), クラスの番号)]。negatives は mine_negatives.py の出力"""
    coco = json.loads((folder / "labels.json").read_text())
    cats = {c["id"]: c["name"] for c in coco["categories"]}
    images = coco["images"]
    if max_images:
        images = images[-max_images:] if last else images[:max_images]
    names = {im["id"]: im["file_name"] for im in images}
    items = [(names[a["image_id"]], tuple(a["bbox"]), LABELS.index(cats[a["category_id"]]))
             for a in coco["annotations"] if a["image_id"] in names]
    if negatives:
        files = set(names.values())
        for n in json.loads(Path(negatives).read_text())["items"]:
            if n["file"] in files:
                items.append((n["file"], tuple(n["bbox"]), LABELS.index(NOT_A_TILE)))
    items.sort(key=lambda t: t[0])  # 同じ写真を続けて読む
    return items


def extract(folder: Path, items, for_training: bool):
    """学習用は箱のまわりも含めて切り抜き（あとでずらして使う）、確認用はアプリと同じ切り抜き方にする"""
    xs, ys = [], []
    current, img = None, None
    for n, (name, (x, y, w, h), label) in enumerate(items):
        if name != current:
            current, img = name, Image.open(folder / "images" / name).convert("RGB")
        if for_training:
            crop = img.crop((round(x - w * CONTEXT), round(y - h * CONTEXT),
                             round(x + w * (1 + CONTEXT)), round(y + h * (1 + CONTEXT))))
            if w > h * LANDSCAPE_RATIO:
                crop = crop.transpose(Image.Transpose.ROTATE_270)
            xs.append(np.asarray(crop.resize((CTX_W, CTX_H), Image.BOX), np.uint8))
        else:
            xs.append(np.asarray(classifier_input(img, x, y, x + w, y + h), np.uint8))
        ys.append(label)
        if n % 10000 == 0:
            print(f"  {folder.name}: {n}/{len(items)}", flush=True)
    return np.stack(xs), np.array(ys, np.int32)


def plain_patches(n, h, w, seed):
    """縁のない平らな面（無地の卓・壁など）の画像を作る。「牌ではない」として使う。

    白（5z）は無地だが、牌の縁や影がある。縁のない平らな面を白と読まないように覚えさせる。
    """
    rng = np.random.default_rng(seed)
    out = np.empty((n, h, w, 3), np.uint8)
    yy, xx = np.mgrid[0:h, 0:w] / max(h, w)
    for i in range(n):
        base = rng.uniform(40, 245) if rng.random() < 0.6 else None  # 灰色・白っぽい色が多め
        color = np.full(3, base) if base is not None else rng.uniform(30, 245, 3)
        color = color * rng.uniform(0.93, 1.07, 3)
        grad = (rng.uniform(-25, 25) * xx + rng.uniform(-25, 25) * yy)[..., None]
        img = color + grad + rng.normal(0, rng.uniform(0, 7), (h, w, 3))
        out[i] = np.clip(img, 0, 255).astype(np.uint8)
    return out


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
    ap.add_argument("--negatives", type=Path, help="学習用の「牌ではない」例（mine_negatives.py の出力）")
    ap.add_argument("--val-negatives", type=Path, help="確認用の「牌ではない」例（mine_negatives.py の出力）")
    ap.add_argument("--plain-negatives", type=int, default=0,
                    help="縁のない平らな面の画像をこの数だけ作って「牌ではない」に足す（確認用にはその 1/8）")
    args = ap.parse_args()

    import tensorflow as tf
    tf.keras.utils.set_random_seed(args.seed)
    args.out.mkdir(parents=True, exist_ok=True)

    t0 = time.time()
    train_items = load_items(args.train, args.negatives, args.max_images)
    val_items = load_items(args.val, args.val_negatives, args.max_images // 4 if args.max_images else None, last=True)
    x_train, y_train = extract(args.train, train_items, True)
    x_val, y_val = extract(args.val, val_items, False)
    val_real = np.array([not name.startswith("s0_") for name, _, _ in val_items])  # merge.py の最初の --src（合成）以外
    if args.plain_negatives:
        n_val = args.plain_negatives // 8
        x_train = np.concatenate([x_train, plain_patches(args.plain_negatives, CTX_H, CTX_W, args.seed + 1)])
        y_train = np.concatenate([y_train, np.full(args.plain_negatives, LABELS.index(NOT_A_TILE), np.int32)])
        x_val = np.concatenate([x_val, plain_patches(n_val, INPUT_H, INPUT_W, args.seed + 2)])
        y_val = np.concatenate([y_val, np.full(n_val, LABELS.index(NOT_A_TILE), np.int32)])
        val_real = np.concatenate([val_real, np.zeros(n_val, bool)])
    bg = LABELS.index(NOT_A_TILE)
    print(f"train: {len(y_train)}（うち牌ではない {(y_train == bg).sum()}）, "
          f"val: {len(y_val)}（実写 {val_real.sum()}、牌ではない {(y_val == bg).sum()}）"
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
    outputs = tf.keras.layers.Dense(len(LABELS), activation="softmax")(x)
    model = tf.keras.Model(inputs, outputs)

    steps = args.epochs * ((len(y_train) + args.batch - 1) // args.batch)
    schedule = tf.keras.optimizers.schedules.CosineDecay(args.lr, steps)
    model.compile(optimizer=tf.keras.optimizers.Adam(schedule),
                  loss=tf.keras.losses.SparseCategoricalCrossentropy(),
                  metrics=["accuracy"])
    model.fit(train_ds, validation_data=val_ds, epochs=args.epochs, verbose=2)

    pred = model.predict(val_ds, verbose=0).argmax(1)
    ok = pred == y_val
    per_class = {c: round(float(ok[y_val == i].mean()), 4) for i, c in enumerate(LABELS) if (y_val == i).any()}
    confusions = {}
    for t, p in zip(y_val[~ok & val_real], pred[~ok & val_real]):
        k = f"{LABELS[t]}→{LABELS[p]}"
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
    (args.out / "tile_classifier_labels.txt").write_text("\n".join(LABELS) + "\n")

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
