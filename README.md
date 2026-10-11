# RiceApp

日本のお米の相場を確認する iOS アプリ（開発中）。

## データ取得

`scripts/fetch_prices.py` が農林水産省の公表資料から価格を取り出し、`data/prices.json` を更新します。
GitHub Actions（`.github/workflows/fetch-prices.yml`）で毎日18時（JST）に自動実行します。数字が変わったときだけコミットされます。

- 店頭価格: スーパーでの販売価格（KSP-POS、全国、週次、円/5kg）
- 相対取引価格: 全銘柄平均と産地品種銘柄別（月次、円/玄米60kg）

手元で試す場合（`pdftotext` が必要: macOS は `brew install poppler`）:

```sh
python3 scripts/fetch_prices.py                                  # Web から取得
python3 scripts/fetch_prices.py --pos-pdf ksppos.pdf --aitai-pdf aitaikakaku.pdf   # ダウンロード済みファイルで
```

## アプリ

- `RiceApp/`：アプリ本体（SwiftUI、iOS 17 以降）
- `RiceWidget/`：ホーム画面ウィジェット（小・中）。アプリと同じ `data/prices.json` を直接読みます
- `Shared/`：アプリとウィジェットで共有するデータの型
- アイコンは `python3 scripts/make_icon.py RiceApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png` で作り直せます（Pillow が必要）

## 出典

農林水産省ウェブサイト（公共データ利用規約 第1.0版）のデータを加工して作成しています。
