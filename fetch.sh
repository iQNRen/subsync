#!/bin/bash
set -e

YEAR=$(date +%Y); MONTH=$(date +%m); DAY=$(date +%d)
FILE="${YEAR}${MONTH}${DAY}"

mkdir -p subs

echo "Fetching https://static.v2rayshare.net/${YEAR}/${MONTH}/${FILE}.txt ..."
curl -s -o subs/merged.txt --connect-timeout 10 --max-time 30 \
  "https://static.v2rayshare.net/${YEAR}/${MONTH}/${FILE}.txt" || echo "FAILED"

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git add subs/
if git diff --cached --quiet; then
  echo "no changes"
else
  git commit -m "daily update $(date +%Y-%m-%d)"
  git push
fi

if [ -n "$PUSHPLUS_TOKEN" ]; then
  SIZE=$(wc -c < subs/merged.txt 2>/dev/null || echo 0)
  STATUS="$([ -s subs/merged.txt ] && echo '✅ 成功' || echo '❌ 失败')"
  curl -s -X POST "http://www.pushplus.plus/send" \
    -H "Content-Type: application/json" \
    -d "{\"token\":\"${PUSHPLUS_TOKEN}\",\"title\":\"订阅更新 ${STATUS}\",\"content\":\"大小: ${SIZE} 字节\",\"template\":\"txt\"}" > /dev/null
fi
