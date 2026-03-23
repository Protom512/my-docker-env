# Docker Server Health Check Skill

## 概要
Dockerコンテナ内でサーバープロセスが起動完了したかを確認するには、ポール方式（リトライ方式）を使用する。

## 手順

### 1. 基本的なポール関数
```bash
wait_for_service() {
    local max_wait="${1:-60}"      # 最大待機時間（秒）
    local interval="${2:-5}"        # チェック間隔（秒）
    local elapsed=0

    while [ ${elapsed} -lt ${max_wait} ]; do
        # ヘルスチェックコマンドを実行
        if health_check_command; then
            echo "Service is ready"
            return 0
        fi

        echo "Waiting for service... (${elapsed}s/${max_wait}s)"
        sleep ${interval}
        elapsed=$((elapsed + interval))
    done

    echo "Service did not become ready within ${max_wait}s" >&2
    return 1
}
```

### 2. ヘルスチェックコマンドの例

#### プロセス確認
```bash
pgrep -f "server_name" >/dev/null 2>&1
```

#### TCPポート確認
```bash
nc -z localhost 8080 >/dev/null 2>&1
# または
timeout 1 bash -c "cat < /dev/null > /dev/tcp/localhost/8080"
```

#### HTTP確認
```bash
curl -sf http://localhost:8080/health >/dev/null 2>&1
```

#### データベース接続確認（isql例）
```bash
isql -S localhost -Usa -P password -b -w 10 <<-SQL
SELECT @@VERSION
GO
EXIT
SQL
```

### 3. 使用例
```bash
# デフォルト60秒待機
wait_for_service

# 120秒待機、3秒間隔
wait_for_service 120 3

# ヘルスチェック結果を変数に格納
if wait_for_service; then
    echo "Service started successfully"
else
    echo "Failed to start service" >&2
    exit 1
fi
```

## 注意点
- 最大待機時間は、サービスの起動時間に基づいて適切に設定する
- チェック間隔が短すぎると負荷が上がる（推奨: 5秒以上）
- ヘルスチェックコマンド自体が失敗してもループが続くよう、エラーハンドリングに注意する
- ログ出力を含め、デバッグ時に進捗がわかるようにする

## アンチパターン
```bash
# ❌ 禁止: 固定時間で待機（非効率・不安定）
sleep 60

# ❌ 禁止: 無限ループ（ハングアップの原因）
while true; do
    if health_check; then
        break
    fi
    sleep 1
done
```
