# CLAUDE.md

このリポジトリで作業する Claude 向けのルールです。

## プロジェクト概要

- 4人打ちリーチ麻雀の点数計算・対局管理アプリ（Flutter / Dart、状態管理は Riverpod）
- 対応: Android / iOS / Web
- 点数計算エンジンは `packages/mahjong_score_engine/`（Flutter 非依存の Dart パッケージ）
- アプリ本体は `lib/`。構成と仕様の詳細は `README.md` を参照

## 作業ルール

- **変更は `main` ブランチに直接コミットして push する**（作業用ブランチやプルリクエストは作らない）
- push する前に、次のチェックをすべて通す
  - `flutter analyze`（警告・エラーなし）
  - `flutter test`（アプリのテスト）
  - `packages/mahjong_score_engine` で `dart test`（点数計算エンジンのテスト）
- 機能を追加・変更したらテストも追加し、`README.md` の機能一覧・説明も更新する
- 利用者が気を付けるべき点（データが消える条件、件数の上限など）は、画面上で分かるように表示する

## 実装の方針

- 対局データ（`GameSession`）は変更不可（immutable）。変更は `copyWith` で新しいオブジェクトを作る。保存処理は「同じオブジェクトかどうか」で変更を判定しているので、この方針を崩さない
- 対局進行のロジックは `lib/features/session/domain/session_logic.dart` に UI と分けて書く
- 保存データの形式を変えるときは `SharedPrefsSessionRepository.formatVersion` を上げ、古い形式のデータも読み込めるようにする（テストも追加する）
- Flutter 3.22 以上で動くようにする

## やりとり

- 説明は日本語で、専門用語は言い換えずに使い、その意味を分かりやすく添える
