# テスト用の写真

- `hand.jpg`: カメラ認識（Web 版）の動作確認に使う、牌が9枚並んだ写真。
  写っている牌（左から）: 5z 6s 1m 3p 3s 3m 1p 5z 9m
  - 出典: [Riichi Mahjong (HUST)](https://universe.roboflow.com/hust-xq5rx/riichi-mahjong)（hust-xq5rx、version 8）の確認用の写真
    `IMG_20231107_230846_jpg.rf.5c5471fbdcb76a9333f64ad3a2d58a44.jpg` から、牌の1列を切り抜いてまわりを写真の色で埋めたもの
    （`tools/tile_model/evaluate.py` の `hand_rows` と同じ作り方）
  - ライセンス: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
