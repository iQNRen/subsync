#!/bin/bash
set -e

YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY=$(date +%d)
FILE_NAME="${YEAR}${MONTH}${DAY}"

mkdir -p subs

# ── 工具函数 ────────────────────────────────────

count_nodes() {
  local file="$1" n=0
  [ ! -s "$file" ] && { echo 0; return; }
  local decoded; decoded=$(base64 -d "$file" 2>/dev/null || echo "")
  if [ -n "$decoded" ]; then
    n=$(echo "$decoded" | grep -cE '^(ss|vmess|trojan|hysteria|vless)://' 2>/dev/null || echo 0)
  fi
  [ "$n" -eq 0 ] && n=$(grep -cE '^(ss|vmess|trojan|hysteria|vless)://' "$file" 2>/dev/null || echo 0)
  [ "$n" -eq 0 ] && n=$(grep -cE '^\s+-\s+{?name' "$file" 2>/dev/null || echo 0)
  [ "$n" -eq 0 ] && n=$(grep -cE '^\s+-\s+type:' "$file" 2>/dev/null || echo 0)
  [ "$n" -eq 0 ] && n=$(grep -cE '.+' "$file" 2>/dev/null || echo 0)
  echo "$n"
}

fetch() {
  local name="$1" url="$2" outfile="subs/${name}.txt"
  echo "[$name] Fetching: $url"
  local code; code=$(curl -s -o "/tmp/sub_${name}.txt" -w "%{http_code}" \
    --connect-timeout 10 --max-time 30 "$url" 2>/dev/null || echo "000")
  if [ "$code" != "200" ] || [ ! -s "/tmp/sub_${name}.txt" ]; then
    echo "[$name] SKIP (HTTP $code)"; return 1
  fi
  cp "/tmp/sub_${name}.txt" "$outfile"
  local nodes; nodes=$(count_nodes "$outfile")
  echo "[$name] OK — $nodes nodes, $(wc -c < "$outfile") bytes"; return 0
}

push_notify() {
  local token="$1" title="$2" content="$3"
  [ -z "$token" ] && return
  curl -s -X POST "http://www.pushplus.plus/send" \
    -H "Content-Type: application/json" \
    -d "$(cat <<EOF
{"token":"${token}","title":"${title}","content":"${content}","template":"txt"}
EOF
)" > /dev/null
  echo "[notify] pushed: ${title}"
}

# ── 订阅源 ──────────────────────────────────────

SUCCESS=0
declare -A NODE_COUNTS

fetch "v2rayshare" \
  "https://static.v2rayshare.net/${YEAR}/${MONTH}/${FILE_NAME}.txt" && \
  SUCCESS=$((SUCCESS + 1)) && NODE_COUNTS["v2rayshare"]=$(count_nodes "subs/v2rayshare.txt") || true

fetch "v2ssr-clash" \
  "https://freenode.v2ssr.net/${YEAR}/${MONTH}/${DAY}-v2ssr.net-clash-vpn-mianfeijiedian.yaml" && \
  SUCCESS=$((SUCCESS + 1)) && NODE_COUNTS["v2ssr-clash"]=$(count_nodes "subs/v2ssr-clash.txt") || true

fetch "v2ssr-v2ray" \
  "https://freenode.v2ssr.net/${YEAR}/${MONTH}/${DAY}-v2ssr.net-ssr-v2ray-vpn-mianfeijiedian.txt" && \
  SUCCESS=$((SUCCESS + 1)) && NODE_COUNTS["v2ssr-v2ray"]=$(count_nodes "subs/v2ssr-v2ray.txt") || true

# ── 合并 ────────────────────────────────────────

> subs/merged.txt
TOTAL_NODES=0
for f in subs/*.txt; do
  [ "$f" = "subs/merged.txt" ] && continue
  name=$(basename "$f" .txt)
  echo "# === ${name} ===" >> subs/merged.txt
  cat "$f" >> subs/merged.txt
  echo "" >> subs/merged.txt
  n=${NODE_COUNTS[$name]:-$(count_nodes "$f")}
  TOTAL_NODES=$((TOTAL_NODES + n))
done

echo "Done: $SUCCESS/3 sources — ${TOTAL_NODES} total nodes"

# ── Git commit & push ───────────────────────────

git config user.name "github-actions[bot]" 2>/dev/null || true
git config user.email "github-actions[bot]@users.noreply.github.com" 2>/dev/null || true
git add subs/

COMMITTED=false
if git diff --cached --quiet; then
  echo "[git] no changes, skip commit"
else
  git commit -m "daily update ${YEAR}-${MONTH}-${DAY} — ${SUCCESS}/3 sources, ${TOTAL_NODES} nodes"
  git push
  COMMITTED=true
  echo "[git] committed & pushed"
fi

# ── Pushplus 通知 ───────────────────────────────

if [ -n "$PUSHPLUS_TOKEN" ]; then
  STATUS_TEXT="$([ "$SUCCESS" -gt 0 ] && echo '✅ 成功' || echo '❌ 失败')"
  NOTIFY_CONTENT="日期: ${YEAR}-${MONTH}-${DAY}
状态: ${STATUS_TEXT}
成功源: ${SUCCESS}/3
节点总数: ${TOTAL_NODES}
提交: ${COMMITTED}"
  push_notify "$PUSHPLUS_TOKEN" "订阅更新 ${STATUS_TEXT}" "$NOTIFY_CONTENT"
fi
