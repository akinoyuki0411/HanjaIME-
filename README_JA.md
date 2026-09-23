# HanjaIME 0.9.4

GureumとlibhangulをベースにしたmacOS用の韓国語2ボル式入力方式です。韓国語を入力して、漢字・日本の新字体・関連する絵文字を選べます。

## インストールと操作

リリースZIPを新しいフォルダに展開し、`repair_and_install.command`を実行してください。現在のインストーラはXcodeとコマンドラインツールを使ってビルド・検証する場合があります。macOSの入力ソースで **HanjaIME 두벌식** を選択します。表示されない場合はログアウトして再度ログインしてください。

入力メニュー → 設定 → 一般 → 日本語で表示言語を変更できます。入力方式は韓国語2ボル式のままです。Spaceで候補を選択・移動し、Enterで確定、Shift+Spaceでハングルのまま空白を入力、Escで変換を取り消します。単語の登録・編集・バックアップは設定 → ユーザー辞書で行います。

設定 → 情報でGitHubの新しいリリースを確認し、検証済みZIPをダウンロードできます。自動確認は初期状態ではオフです。有効にすると1日ごとに確認します。ダウンロード後は手動でインストールしてください。新バージョンの初回起動時に変更履歴が一度表示されます。

Apple Silicon向けの開発署名版です。Developer IDによる公証とIntel版は含まれていません。公式Gureumは別途保持されます。インストール先は `~/Library/Input Methods/HanjaIME.app` です。

お問い合わせ: akinoyuki0122@gmail.com · [不具合報告](https://github.com/akinoyuki0411/HanjaIME-/issues) · [ソースコード](https://github.com/akinoyuki0411/HanjaIME-)。支援による支払いはまだ受け付けていません。

ユーザー辞書と学習履歴はこのMacに保存され、配布物には含まれません。NAVER辞書には選択した語だけを検索時に送信します。任意の更新確認はGitHubに接続します。ライセンスと対応ソースは THIRD_PARTY_NOTICES.md、licenses/、CorrespondingSource/ を参照してください。
