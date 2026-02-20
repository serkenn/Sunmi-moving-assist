# Sunmi Inventory App

Sunmi V1-B18 (Android 5.1 / API 22) 向けの在庫管理アプリです。  
バーコード/QRスキャン、商品候補検索、AI分析、Google Sheets連携、ラベル印刷に対応しています。

## 主な機能

- バーコード / QR スキャン
  - スキャン値から `ローカルDB` / `OpenFoodFacts` / `Rakuten API` / `Gemini` を使って候補検索
- 商品名から候補検索
  - `DB / API / AI` 候補を一覧表示して確定登録
- 商品フォームでバーコード再スキャン
  - 候補確定後にバーコード未入力でもフォーム上でスキャン入力可能
- 写真管理
  - Rakuten候補に画像URLがあれば自動反映
  - 画像が無い場合はフォームから端末カメラ撮影して保存可能
- AI分析
  - 商品の引っ越し判定・保管場所・信頼度を推定
- Google Sheets エクスポート
  - 先頭シートへヘッダ付きで上書き出力（画像URL列を含む）
- Sunmi プリンタ連携
  - 商品タグ、バーコード、QR印刷

## Android 5.1 (API 22) 対応

- `android/app/build.gradle.kts` の `minSdk` は `22`
- Flutter は `3.38` 系を前提
- 写真撮影は API 22 互換維持のため、`image_picker` ではなく
  `MethodChannel(pos_steward_camera)` + AndroidネイティブカメラIntentで実装

## 初期設定（アプリ内）

`設定 -> APIキー設定` で以下を入力します。

- Gemini APIキー
- Rakuten Application ID
- Rakuten Access Key
- Rakuten Affiliate ID（任意）
- Google Sheets Spreadsheet ID（ID または URL）
- Google Service Account JSON（JSON文字列）

保存時に接続テストを実行できます。

## Google Sheets 連携の前提

1. Google Cloud で Service Account を作成
2. Google Sheets API を有効化
3. 対象スプレッドシートを Service Account のメールアドレスに `編集者` で共有
4. 上記の Spreadsheet ID / Service Account JSON をアプリ設定へ登録

補足:

- エクスポート時は先頭シートの `A:Z` をクリアしてから書き込みます
- 出力列に `画像URL` を含みます

## Build (Android 5.1)

```bash
FLUTTER_51=/path/to/flutter_3.38/bin/flutter
$FLUTTER_51 pub get
$FLUTTER_51 build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

## 開発時の確認コマンド

```bash
/path/to/flutter_3.38/bin/flutter analyze
/path/to/flutter_3.38/bin/dart format lib
```

## ログ採取（不具合調査）

```bash
adb logcat -c
adb logcat -v threadtime > /tmp/sunmi_api_save_live.log
```

必要に応じてログマーカー:

```bash
adb shell log -t API_SAVE_TEST YOUR_MARKER
```
