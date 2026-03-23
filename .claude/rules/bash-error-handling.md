# Bash Error Handling Rule

## Rule
**すべてのbashスクリプトは `set -euo pipefail` を使用すること。**

## Rationale
- `set -e`: コマンドが失敗したら即座にスクリプトを終了する
- `set -u`: 未定義変数の使用をエラーにする
- `set -o pipefail`: パイプラインの途中でエラーがあった場合、全体の戻り値を失敗にする

## 禁止するパターン
```bash
# ❌ 禁止: エラーを見逃す可能性がある
set -xuo pipefail

# ❌ 禁止: エラーハンドリングなし
some_command || true  # 明確な理由なしで使用禁止
```

## 推奨するパターン
```bash
#!/usr/bin/env bash
set -euo pipefail

# エラーハンドリングが必要な場合は明示的に
if ! some_command; then
    echo "Error: some_command failed" >&2
    exit 1
fi

# またはコマンドの結果を変数に格納
output=$(some_command) || {
    echo "Error: some_command failed" >&2
    exit 1
}
```

## 例外
一時的にエラーを無視する必要がある場合は、理由をコメントに記述すること:
```bash
# 一時ファイルの削除に失敗しても続行
rm -f /tmp/file || true
```
