# codex-account-manager

Codex CLIを複数アカウントで使い分けるための、小さなローカルルーターです。
アカウントごとに`CODEX_HOME`を分け、カレントディレクトリまたは明示指定から
使用する認証を選びます。

認証ファイルをコピーして差し替える方式ではありません。各アカウントの
`auth.json`、セッション履歴、状態DBは、それぞれの`CODEX_HOME`内に独立して保存されます。
一方、`config.toml`、`AGENTS.md`、skills、pluginsなどは既定アカウントのホームから
シンボリックリンクで共有できます。

## 必要なもの

- インストール済みのCodex CLI
- Python 3.11以降
- Bash（インストーラーとラッパーに使用）

Codexは、file credential storeを使う場合に認証情報を`$CODEX_HOME/auth.json`へ保存します。
詳しくは[Codexの認証ドキュメント](https://learn.chatgpt.com/docs/auth)と
[設定リファレンス](https://learn.chatgpt.com/docs/config-file/config-reference)を参照してください。

## インストール

```bash
git clone <repository-url> codex-account-manager
cd codex-account-manager
./install.sh --shell-hook
exec "$SHELL" -l
```

既定では、次のファイルを作成します。

- `~/.local/bin/codex-account`: 管理CLI
- `~/.local/bin/codex`: Codexを管理CLIへ渡すラッパー
- `~/.config/codex-accounts/config.toml`: ユーザー固有設定（初回のみ）

`--shell-hook`は`~/.bashrc`または`~/.zshrc`へ短い管理ブロックを追加します。
mise、asdf、npmなどがPATHの先頭を変更しても、ラッパーを確実に呼ぶためのものです。
設定ファイルがすでにある場合、インストーラーは上書きしません。既存の同名実行ファイルを
更新する場合は、`~/.local/share/codex-account/backups/`へ退避します。

Codex本体を自動検出できない場合や、複数のインストールがある場合は明示できます。

```bash
./install.sh --codex-binary /absolute/path/to/codex --shell-hook
```

カスタムインストール先も指定できます。

```bash
./install.sh \
  --prefix "$HOME/.local" \
  --config "$HOME/.config/codex-accounts/config.toml"
```

## 最初の設定

初期設定には`default`アカウントだけがあり、通常の`~/.codex`を使います。
追加アカウントはコマンドで作成できます。

```bash
codex-account add work --label "Work" --path "$HOME/src/work"
codex-account login work
```

まとめて追加・ログインする場合はこちらです。

```bash
codex-account login work --label "Work" --path "$HOME/src/work"
```

以後はディレクトリに応じて自動選択されます。

```bash
cd "$HOME/src/work/project-a"
codex
```

一時的にアカウントを指定することもできます。

```bash
codex --account work
codex --account=work exec "テストを実行して"
CODEX_ACCOUNT=work codex
```

`codex -C DIR`と`codex exec -C DIR`の`DIR`も選択対象になります。

## 設定ファイル

`~/.config/codex-accounts/config.toml`を直接編集しても構いません。

```toml
version = 1
default_account = "personal"
announce = true
codex_binary = "/absolute/path/to/codex"
shared_home = "$HOME/.codex"

[accounts.personal]
label = "Personal"
home = "$HOME/.codex"

[accounts.work]
label = "Work"
home = "$HOME/.codex/auth-work"

[accounts.client_a]
label = "Client A"
home = "$HOME/.codex/auth-client-a"

[paths]
"$HOME/src/company" = "work"
"$HOME/src/company/client-a" = "client_a"
```

パス規則は最長一致です。この例では`~/src/company/client-a`配下だけ`client_a`、
その他の`~/src/company`配下は`work`が選ばれます。どの規則にも一致しなければ
`default_account`を使います。

環境変数でも一時的に変更できます。

- `CODEX_ACCOUNT`: 起動するアカウント名
- `CODEX_ACCOUNTS_CONFIG`: 設定ファイルの場所
- `CODEX_ACCOUNT_REAL_CODEX`: Codex本体の場所

## 管理コマンド

```bash
codex-account list
codex-account which "$PWD"
codex-account status --all
codex-account prepare
codex-account add NAME [--label LABEL] [--home DIR] [--path DIR]
codex-account map NAME DIR
codex-account login [NAME] [--device-auth]
codex-account logout [NAME] --yes
codex-account doctor [NAME]
codex-account probe [NAME] --yes
```

`status`はtokenそのものを表示せず、有効期限とrefresh tokenの有無だけを読み取ります。
`probe --yes`だけはモデル呼び出しを1回行い、自動refreshを含む実通信経路を確認します。
`logout`は認証を削除するため、`--yes`を必須にしています。

## セッションについて

セッション履歴も`CODEX_HOME`ごとに分離されるため、別アカウントで作ったセッションを
そのまま`codex resume`する用途には向きません。このツールは認証と状態の安全な分離を
優先しており、アカウント間のセッションDB統合は行いません。

## 開発

```bash
make test
```

テストは一時HOMEと偽のCodex CLIを使い、実際の認証情報やモデル呼び出しには触れません。
