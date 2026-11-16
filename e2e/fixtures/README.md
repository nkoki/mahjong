# テスト用の写真

- `hand.jpg`: カメラ認識（Web 版）の動作確認に使う、牌が9枚並んだ写真。
  写っている牌（左から）: 5z 6s 1m 3p 3s 3m 1p 5z 9m
  - 出典: [Riichi Mahjong (HUST)](https://universe.roboflow.com/hust-xq5rx/riichi-mahjong)（hust-xq5rx、version 8）の確認用の写真
    `IMG_20231107_230846_jpg.rf.5c5471fbdcb76a9333f64ad3a2d58a44.jpg` から、牌の1列を切り抜いてまわりを写真の色で埋めたもの
    （`tools/tile_model/evaluate.py` の `hand_rows` と同じ作り方）
  - ライセンス: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
- `guided_camera.mjpeg`: 枠つきの撮影（Web 版）の動作確認で、ブラウザの偽のカメラに流す映像（同じ1コマを並べたもの）。
  鳴いた牌の枠に「中のポン」と「2・3・4筒のチー」、手牌の枠に7枚（2萬 3萬 4萬 5索 5索 6筒 7筒）、和了牌の枠に 8筒 を置いてある。
  偽のカメラは内側のカメラとして扱われ、映像が鏡のように左右反転して表示されるので、牌は左右を入れ替えた位置に置いてある。
  - 作り方: `make_guided_camera.py`
  - 出典: [Riichi Mahjong (HUST)](https://universe.roboflow.com/hust-xq5rx/riichi-mahjong)（hust-xq5rx、version 8）の確認用の写真
    `IMG_20231219_161834_jpg.rf.8df20517907a5377c339f016aaef511f.jpg` から牌を1枚ずつ切り抜いて並べ直したもの
  - ライセンス: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
