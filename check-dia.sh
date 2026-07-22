#!/bin/bash
# set -e は使わない（grepが0件マッチでexit 1を返すため）

# ===== 監視対象 =====
TOBUS_URL="https://www.kotsu.metro.tokyo.jp/pickup_information/news/bus.html"
METRO_URL="https://www.tokyometro.jp/news/"
JR_URL="https://www.jreast.co.jp/press/"
KW="ダイヤ改正|ダイヤ変更|時刻改正|時刻変更"
JSON="dia-alert.json"

# ===== 各ページのキーワード出現回数を取得 =====
# grepが0件でもエラーにならないよう || true で握りつぶす
tobus=$(curl -sL "$TOBUS_URL" 2>/dev/null | grep -coE "$KW" || true)
metro=$(curl -sL "$METRO_URL" 2>/dev/null | grep -coE "$KW" || true)
jr=$(curl -sL "$JR_URL" 2>/dev/null | grep -coE "$KW" || true)

# 空だったら0に正規化
tobus=${tobus:-0}
metro=${metro:-0}
jr=${jr:-0}

echo "取得結果: tobus=$tobus metro=$metro jr=$jr"

# ===== 前回ベースライン読み込み =====
prev_tobus=$(jq -r '.baseline.tobus // 0' "$JSON" 2>/dev/null || echo 0)
prev_metro=$(jq -r '.baseline.metro // 0' "$JSON" 2>/dev/null || echo 0)
prev_jr=$(jq -r '.baseline.jr // 0' "$JSON" 2>/dev/null || echo 0)

echo "前回値: tobus=$prev_tobus metro=$prev_metro jr=$prev_jr"

# ===== 既存alerts読み込み =====
existing_alerts=$(jq -c '.alerts // []' "$JSON" 2>/dev/null || echo '[]')

# ===== 増加検知 → alert追加 =====
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TODAY=$(date -u +%Y-%m-%d)
new_alerts="$existing_alerts"

if [ "$tobus" -gt "$prev_tobus" ]; then
  echo "都営バス: キーワード増加 ($prev_tobus -> $tobus)"
  new_alerts=$(echo "$new_alerts" | jq --arg d "$TODAY" --arg s "都営バス" '. + [{"source":$s,"date":$d}]')
fi
if [ "$metro" -gt "$prev_metro" ]; then
  echo "東京メトロ: キーワード増加 ($prev_metro -> $metro)"
  new_alerts=$(echo "$new_alerts" | jq --arg d "$TODAY" --arg s "東京メトロ" '. + [{"source":$s,"date":$d}]')
fi
if [ "$jr" -gt "$prev_jr" ]; then
  echo "JR東日本: キーワード増加 ($prev_jr -> $jr)"
  new_alerts=$(echo "$new_alerts" | jq --arg d "$TODAY" --arg s "JR東日本" '. + [{"source":$s,"date":$d}]')
fi

# ===== JSON更新（ベースラインは常に最新値に更新） =====
jq -n \
  --arg lc "$NOW" \
  --argjson tb "$tobus" \
  --argjson mt "$metro" \
  --argjson jr "$jr" \
  --argjson al "$new_alerts" \
  '{lastChecked:$lc, baseline:{tobus:$tb, metro:$mt, jr:$jr}, alerts:$al}' > "$JSON"

echo "完了:"
cat "$JSON"
