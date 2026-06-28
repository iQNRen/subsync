#!/bin/bash
set -e

YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY=$(date +%d)
FILE_NAME="${YEAR}${MONTH}${DAY}"

mkdir -p subs

fetch() {
  local name="$1" url="$2" outfile="subs/${name}.txt"
  echo "[$name] Fetching: $url"
  local code; code=$(curl -s -o "/tmp/sub_${name}.txt" -w "%{http_code}" \
    --connect-timeout 10 --max-time 30 "$url" 2>/dev/null || echo "000")
  if [ "$code" != "200" ] || [ ! -s "/tmp/sub_${name}.txt" ]; then
    echo "[$name] SKIP (HTTP $code)"; return 1
  fi
  cp "/tmp/sub_${name}.txt" "$outfile"
  local size; size=$(wc -c < "$outfile")
  echo "[$name] OK — $size bytes"; return 0
}

fetch "v2rayshare" \
  "https://static.v2rayshare.net/${YEAR}/${MONTH}/${FILE_NAME}.txt" || true

# Git
git config user.name "github-actions[bot]" 2>/dev/null || true
git config user.email "github-actions[bot]@users.noreply.github.com" 2>/dev/null || true
git add subs/

if git diff --cached --quiet; then
  echo "[git] no changes"
else
  git commit -m "daily update $(date +%Y-%m-%d)"
  git push
fi

# Pushplus
if [ -n "$PUSHPLUS_TOKEN" ]; then
  EXISTS=0; [ -s subs/v2rayshare.txt ] && EXISTS=1
  STATUS="$([ "$EXISTS" = "1" ] && echo '✅ 成功' || echo '❌ 失败')"
  FILE_SIZE=$(wc -c < subs/v2rayshare.txt 2>/dev/null || echo 0)
  curl -s -X POST "http://www.pushplus.plus/send" \
    -H "Content-Type: application/json" \
    -d "{\"token\":\"${PUSHPLUS_TOKEN}\",\"title\":\"订阅更新 ${STATUS}\",\"content\":\"状态: ${STATUS}\n大小: ${FILE_SIZE} 字节\",\"template\":\"txt\"}" > /dev/null
fi
