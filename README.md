# 麻雀点数計算アプリ（4人打ち）

4人打ちリーチ麻雀の **点数計算・対局管理・戦績記録** を行う Flutter アプリです。

- フレームワーク: Flutter 3.22 以上 / Dart 3.4 以上
- 状態管理: Riverpod（`flutter_riverpod`）
- 対応: Android / iOS（確認用に Web も同梱）

## 実行方法

```bash
cd mahjong_app
flutter pub get
flutter run            # 実機・エミュレータで起動
flutter test           # アプリのテスト（対局進行ロジック・画面操作）
cd packages/mahjong_score_engine && dart test   # 点数計算エンジンのテスト
```

## 機能

| 機能 | 内容 |
|---|---|
| 新規対局 | 4人の名前、半荘戦／東風戦、持ち点（配給原点）、返し、ウマ、トビの有無 |
| ダッシュボード | 現在の局・本場・供託、4人の点数・自風・順位・トップとの差、立直の宣言／取消、1つ前に戻す |
| 和了入力 | 和了者・ロン／ツモ・放銃者、手牌（牌パレットで入力）、和了牌、鳴き（チー・ポン・明槓・加槓・暗槓、赤5指定可）、ドラ表示牌・裏ドラ表示牌、状況役（立直・ダブル立直・一発・嶺上開花・槍槓・海底・河底・天和・地和） |
| 計算結果 | 役一覧と翻数、符の内訳、満貫などの名称、点数（例: 1300-2600 / 4000オール）、全員の点数移動（本場・供託込み） |
| 流局入力 | 荒牌平局（ノーテン罰符）、流し満貫、九種九牌、四風連打、四家立直、四開槓、三家和 |
| 戦績 | 対局一覧、最終順位とポイント（ウマ・オカ込み）、局ごとの点数増減表と内容 |
| カメラ認識 | 設計のみ（`lib/features/camera/tile_recognizer.dart`。Qwen API 用の指示文と応答解析を用意、通信部分は未実装） |

## 採用しているルール

- 喰いタンあり、赤ドラあり（各色の5に1枚ずつ）
- 切り上げ満貫なし（4翻30符 = 7700点 / 親11600点）
- 数え役満あり（13翻以上）
- ダブル役満あり: 四暗刻単騎、国士無双十三面待ち、純正九蓮宝燈、大四喜。役満の複合あり
- 連風牌（場風かつ自風）の雀頭は4符
- 本場: ロン300点 / ツモ各100点、供託リーチ棒は和了者が獲得（流局時は持ち越し、終局時はトップが獲得）
- 親の和了・親テンパイの流局・途中流局は連荘（本場+1）。子の和了は親流れで本場0に
- 終局: 最終局が終わったとき、トビ（0点未満、設定時）、オーラスで親が和了してトップのとき（和了止め）、またはメニューから手動で終了
- 同点の順位は起家に近い人が上位
- 複数の解釈ができる手（例: 二盃口と七対子、三暗刻と一盃口、両面と嵌張）は最も点数が高いものを採用（高点法）

## ディレクトリ構成

```text
mahjong_app/
├── lib/
│   ├── main.dart                      アプリの入口（ProviderScope・テーマ）
│   ├── core/                          テーマ・点数の表示形式・画面遷移
│   ├── shared/widgets/                牌の表示（TileView）・牌パレット（TilePalette）
│   └── features/
│       ├── session/
│       │   ├── domain/models.dart         対局・ルール・局の記録のデータ型
│       │   ├── domain/session_logic.dart  点数移動・連荘・親流れ・終局の処理（UI非依存）
│       │   ├── session_providers.dart     Riverpod の状態（インメモリ保存）
│       │   └── screens/                   ホーム・新規対局・ダッシュボード
│       ├── win/                       和了入力・鳴き入力ダイアログ・計算結果
│       ├── draw/                      流局入力
│       ├── history/                   戦績一覧・戦績詳細
│       └── camera/                    カメラ認識のインターフェース（準備中）
├── packages/
│   └── mahjong_score_engine/          点数計算エンジン（Flutter 非依存の Dart パッケージ）
│       └── lib/src/
│           ├── types.dart             牌・鳴き・和了入力・役・計算結果の型
│           ├── tile_utils.dart        牌の操作（ソート・ドラ・赤ドラ・牌名）
│           ├── decomposer.dart        面子分解・七対子／国士無双の判定
│           ├── hand_context.dart      1つの解釈（面子分解＋和了牌の位置＋待ちの形）
│           ├── yaku_judge.dart        役判定（通常役・役満）
│           ├── fu_calculator.dart     符計算
│           └── score_calculator.dart  入力チェック・高点法・点数と支払額の計算
└── test/                              アプリのテスト
```

## 点数計算エンジンの使い方

```dart
import 'package:mahjong_score_engine/mahjong_score_engine.dart';

final result = ScoreCalculator.calculate(
  const WinInput(
    handTiles: ['2m','3m','4m','5mr','6m','7p','8p','9p','2s','3s','4s','5s','5s'],
    winningTile: '1m',
    melds: [],
    winType: 'tsumo',
    isRiichi: true,
    isIppatsu: false,
    isDoubleRiichi: false,
    doraTiles: ['4m'],
    uraDoraTiles: [],
    roundWind: '1z',  // 場風: 東
    playerWind: '2z', // 自風: 南（子）
  ),
  honba: 0,
  riichiSticks: 1,
);
print(result); // 役・翻・符・点数
```

牌の表記: `1m`〜`9m`（萬子）、`1p`〜`9p`（筒子）、`1s`〜`9s`（索子）、`1z`〜`7z`（東南西北白發中）、赤5は `5mr` `5pr` `5sr`。

ツモ和了の `PaymentDetail.playerPayments` の `playerId` は **支払う人の自風**（0=東家(親), 1=南家, 2=西家, 3=北家）です。

## 未実装（今後の予定）

- 3人打ち（3麻）対応
- カメラによる手牌認識（Qwen API との通信部分）
- データベースによる永続化（現在はメモリ上のみ。アプリを終了すると記録は消えます）
- ダブロン（2人同時のロン和了）、包（パオ）、切り上げ満貫などのルール切り替え
