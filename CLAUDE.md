# HaYaku — Claude Code 向けガイド

## プロジェクト概要

macOS メニューバー常駐の翻訳アプリ。グローバルショートカット（デフォルト ⌘⇧T）で選択テキストを OpenAI API で翻訳し、ポップアップにストリーミング表示する。Swift Package Manager の executable ターゲットを `.app` バンドルに手動でパッケージングしている。

- **言語**: Swift 5.9+、macOS 13+
- **依存**: `KeyboardShortcuts`（sindresorhus）のみ
- **Bundle ID**: `com.personal.HaYaku`

## ドキュメント更新ルール

**仕様面の変更を加えたら、同セッション内で `README.md` と `CLAUDE.md` の該当箇所を必ず更新すること。**

更新が必要な変更の例:

- 翻訳先言語・言語判定ロジック
- デフォルトモデル・モデル選択肢
- システムプロンプト
- 翻訳フロー（テキスト取得→API→表示の流れ）
- ストリーミング有無・SSE パース方式
- ファイル構成（ファイルの追加・削除・改名）
- ショートカットのデフォルト値
- 設定 UI の項目
- `config.json` のスキーマ
- TCC / アクセシビリティ権限まわりの挙動

更新不要な変更の例（ドキュメントと矛盾が生じない純粋な内部リファクタ）:

- 関数・変数の改名
- ファイル内の関数分割・整理
- テストの追加

**チェック対象**: README の「機能」「設定の表」「動作のしくみ」「翻訳プロンプト」、CLAUDE.md の「ファイル構成」「翻訳フロー」「翻訳プロンプト」「ストリーミング UI」。

## ビルドとインストール

```bash
swift build                  # デバッグビルド（動作確認用）
./build-app.sh               # リリースビルド → .app バンドル生成
./install.sh                 # build-app.sh + /Applications/ 配置 + TCC リセット + 起動
swift package clean          # SPM キャッシュが古い場合はこれを先に実行
```

**注意**: `./install.sh` は毎回 `tccutil reset Accessibility com.personal.HaYaku` を実行するため、インストール後にアクセシビリティ権限の再付与が必要。

## ファイル構成と役割

```text
Sources/HaYaku/
├── main.swift                          # エントリポイント（NSApplication.shared + AppDelegate）
├── HaYakuApp.swift             # AppDelegate: NSStatusItem, NSMenu, applicationDidFinishLaunching
├── AppState.swift                      # @MainActor ObservableObject: 翻訳フロー全体を管理
├── Clipboard/
│   └── SelectionCapture.swift          # ★ テキスト取得（最重要・複雑）
├── Translation/
│   └── OpenAIClient.swift              # Chat Completions API ストリーミング呼び出し
├── Hotkey/
│   └── HotkeyManager.swift             # KeyboardShortcuts ライブラリでグローバル HK 登録
├── Settings/
│   ├── ConfigStore.swift               # ~/Library/Application Support/HaYaku/config.json
│   ├── SettingsView.swift              # SwiftUI 設定画面
│   └── SettingsWindowController.swift  # NSWindowController で SettingsView をホスト
└── UI/
    ├── PopupWindowController.swift     # 翻訳結果ポップアップウィンドウ管理
    ├── PopupViewModel.swift            # @MainActor ObservableObject: TranslationPopupState を保持
    ├── TranslationPopupView.swift      # ポップアップの SwiftUI ビュー
    └── MenuBarContent.swift            # メニューバーアイコン用（現在 NSMenu で使用）
```

## 翻訳フロー（AppState.translateSelectedText）

1. アクセシビリティ権限チェック
2. `SelectionCapture.captureWithDiagnostics()` でテキスト取得（後述）
3. `popupWindowController.showLoading()` でローディング表示
4. `OpenAIClient.translateStream(_:apiKey:model:)` で SSE ストリーミング開始
5. 初回 delta 受信時に `popupWindowController.startStreaming(original:)` でポップアップを結果表示モードに切り替え
6. 以降の delta を `popupWindowController.appendDelta(_:)` で逐次追記
7. ストリーム完了後 `translationResult` に蓄積値を保存

**重要**: ポップアップ（`showLoading` 含む）はテキスト取得**後**に表示する。取得前に表示するとウィンドウがフォーカスを奪い、Cmd+C フォールバックが HaYaku 自身に飛ぶ。

## 選択テキスト取得（SelectionCapture.swift）

二段構え:

### 第一手: AX API

`NSWorkspace.shared.frontmostApplication.processIdentifier` → `AXUIElementCreateApplication(pid)` → `kAXFocusedUIElement` → `kAXSelectedTextAttribute`

- **システムワイドの `AXUIElementCreateSystemWide()` は使わない**: `kAXFocusedUIElement` が `AXWindow` を返してしまい、その配下のテキスト要素が取れないアプリがある
- `kAXSelectedText` で取れない場合は `kAXSelectedTextRange` + `kAXValue` で切り出し、さらに失敗なら子孫要素を BFS 探索（maxDepth=5）

### フォールバック: Cmd+C 合成

- `CGEventSource(stateID: .privateState)` + `.cghidEventTap` でイベント送信（`.cgSessionEventTap` は一部アプリに届かない）
- 修飾キー（⌘⇧）が離れるまで最大 1 秒待機してから合成
- `NSPasteboard.changeCount` を 30ms × 20 回ポーリング

診断情報は `CaptureResult.diagnosticSummary` に記録され、失敗時のエラーメッセージに `[診断]` として表示される。

## 翻訳プロンプト（OpenAIClient.swift の `systemPrompt`）

翻訳先は常に日本語固定。入力が既に日本語の場合はそのまま返す。

```text
You are a professional multilingual translator and localization expert.

Your task is to translate the user's input into natural, fluent Japanese (日本語).
The output must be:
- accurate
- natural
- context-aware
- culturally appropriate
- fluent for native Japanese speakers

Translation rules:
- Preserve the original meaning exactly.
- Prioritize natural phrasing over literal word-by-word translation.
- Preserve tone, nuance, politeness level, and intent.
- Keep technical terminology consistent and use terms commonly used by native Japanese professionals in the relevant field.
- Do not omit information.
- Do not add explanations or commentary.
- Do not summarize.
- If the source is ambiguous, choose the most contextually natural interpretation.
- Preserve formatting, markdown, emojis, bullet points, and line breaks whenever possible.
- Preserve names, URLs, code, and identifiers unless localization is explicitly required.
- If the input is already in Japanese, return it unchanged.

Output only the translated text.
```

- `temperature: 0.2`、タイムアウト 60 秒
- リクエスト本文に `stream: true` を含め、レスポンスを SSE で受信
- `for try await line in bytes.lines` で `data:` プレフィックス行を逐次パース、`[DONE]` で終了

## ストリーミング UI

- `PopupWindowController` は `init` で `NSHostingView` を **1 度だけ** 生成する（delta ごとに再生成しない）
- `PopupViewModel`（`@MainActor ObservableObject`）の `@Published var state: TranslationPopupState` が更新されると SwiftUI が差分描画する
- `appendDelta(_:)` は VM の状態を更新した後、`DispatchQueue.main.async { resizeToFit() }` でウィンドウ高さをコンテンツに追従させる
- ウィンドウが閉じられている（`!window.isVisible`）場合は `appendDelta` を無視してストリームを空読みする

## macOS 固有の地雷

### 1. ad-hoc 署名 + TCC キャッシュ

`codesign --sign -` するたびにバイナリのハッシュが変わり、TCC（アクセシビリティ権限）データベースが「別アプリ」として扱う。システム設定上チェック済みでも権限が通らなくなる。

**対処**: `tccutil reset Accessibility com.personal.HaYaku` → アプリ起動 → 権限再付与

`install.sh` はこのリセットを自動実行するが、権限の再付与はユーザーが手動で行う必要がある。

### 2. メニューバーアイコンが見えない

Bartender などのメニューバー整理アプリが新しいアイコンを自動的に隠すことがある。`NSStatusItem` を直接生成しているので、Bartender の管理画面で表示設定を確認。

SwiftUI の `MenuBarExtra` は使っていない（`.app` バンドル化した SPM executable との相性問題）。

### 3. SPM ビルドキャッシュ

`./install.sh` がリリースビルドに古いキャッシュを使い、ソース変更が反映されないことがある。`swift package clean` してから再実行すること。

### 4. @MainActor 境界

`AppDelegate`・`AppState`・`SelectionCapture`・`PopupViewModel`・`PopupWindowController` はすべて `@MainActor`。非同期処理は `Task { @MainActor in ... }` でラップ。Swift 6 Strict Concurrency に対応済み。
