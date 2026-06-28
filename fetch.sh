#!/bin/bash
set -e

YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY=$(date +%d)
FILE_NAME="${YEAR}${MONTH}${DAY}"

mkdir -p subs

# ── 工具函数 ────────────────────────────────────

count_nodes() {
  local file="$1"
  local n=0

  if [ ! -s "$file" ]; then
    echo 0
    return
  fi

  # 尝试 base64 解码
  local decoded
  decoded=$(base64 -d "$file" 2>/dev/null || echo "")

  if [ -n "$decoded" ]; then
    n=$(echo "$decoded" | grep -cE '^(ss|vmess|trojan|hysteria|vless)://' 2>/dev/null || echo 0)
  fi

  # 没找到 → 直接按行数（每行一个节点）
  if [ "$n" -eq 0 ]; then
    n=$(grep -cE '^(ss|vmess|trojan|hysteria|vless)://' "$file" 2>/dev/null || echo 0)
  fi

  # 还不对 → 可能是 Clash YAML
  if [ "$n" -eq 0 ]; then
    n=$(grep -cE '^\s+-\s+{?name' "$file" 2>/dev/null || echo 0)
  fi
  if [ "$n" -eq 0 ]; then
    n=$(grep -cE '^\s+-\s+type:' "$file" 2>/dev/null || echo 0)
  fi

  # 兜底：非空行数
  if [ "$n" -eq 0 ]; then
    n=$(grep -cE '.+' "$file" 2>/dev/null || echo 0)
  fi

  echo "$n"
}

fetch() {
  local name="$1"
  local url="$2"
  local outfile="subs/${name}.txt"

  echo "[$name] Fetching: $url"

  local code
  code=$(curl -s -o "/tmp/sub_${name}.txt" -w "%{http_code}" \
    --connect-timeout 10 --max-time 30 "$url" 2>/dev/null || echo "000")

  if [ "$code" != "200" ] || [ ! -s "/tmp/sub_${name}.txt" ]; then
    echo "[$name] ✗ SKIP (HTTP $code)"
    return 1
  fi

  cp "/tmp/sub_${name}.txt" "$outfile"
  local nodes
  nodes=$(count_nodes "$outfile")
  echo "[$name] ✓ OK — $nodes nodes, $(wc -c < "$outfile") bytes"
  return 0
}

# ── 订阅源 ──────────────────────────────────────

SUCCESS=0
declare -A NODE_COUNTS

if fetch "v2rayshare" \
  "https://static.v2rayshare.net/${YEAR}/${MONTH}/${FILE_NAME}.txt"; then
  SUCCESS=$((SUCCESS + 1))
  NODE_COUNTS["v2rayshare"]=$(count_nodes "subs/v2rayshare.txt")
fi

if fetch "v2ssr-clash" \
  "https://freenode.v2ssr.net/${YEAR}/${MONTH}/${DAY}-v2ssr.net-clash-vpn-mianfeijiedian.yaml"; then
  SUCCESS=$((SUCCESS + 1))
  NODE_COUNTS["v2ssr-clash"]=$(count_nodes "subs/v2ssr-clash.txt")
fi

if fetch "v2ssr-v2ray" \
  "https://freenode.v2ssr.net/${YEAR}/${MONTH}/${DAY}-v2ssr.net-ssr-v2ray-vpn-mianfeijiedian.txt"; then
  SUCCESS=$((SUCCESS + 1))
  NODE_COUNTS["v2ssr-v2ray"]=$(count_nodes "subs/v2ssr-v2ray.txt")
fi

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

# ── 写入状态文件供 workflow 用 ─────────────────────
cat > subs/status.txt <<EOF
fetch_date=$YEAR-$MONTH-$DAY
sources=$SUCCESS
total_nodes=$TOTAL_NODES
EOF

echo "────────────────────────────"
echo "Files in subs/:"
ls -lh subs/ | grep -v status.txt
echo "────────────────────────────"
echo "✓ $SUCCESS/3 sources — ${TOTAL_NODES} total nodes"
echo "────────────────────────────"
