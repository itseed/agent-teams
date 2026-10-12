#!/usr/bin/env bash
# ตั้ง issue เป็น In progress + assignee itseed บน project #11
# ใช้: ./scripts/issue-wip.sh <web|api> <issue-number> [todo|inprogress|done]
set -euo pipefail
REPO_KIND="${1:?ระบุ web หรือ api}"; NUM="${2:?ระบุเลข issue}"; STATE="${3:-inprogress}"
case "$REPO_KIND" in
  web) DIR=/Users/kriangkrai/project/health-compass-ai-web; SLUG=health-compass-ai-web ;;
  api) DIR=/Users/kriangkrai/project/health-compass-ai-api; SLUG=health-compass-ai-api ;;
  *) echo "repo ต้องเป็น web หรือ api"; exit 1 ;;
esac
PROJ=11; OWNER=itseed; PROJ_ID="PVT_kwHOAGDVRM4BgnbP"; FID="PVTSSF_lAHOAGDVRM4BgnbPzhfmTtg"
case "$STATE" in
  todo) OPT=f75ad846 ;; inprogress) OPT=47fc9ee4 ;; done) OPT=98236657 ;;
  *) echo "state ต้องเป็น todo|inprogress|done"; exit 1 ;;
esac
( cd "$DIR" && gh issue edit "$NUM" --add-assignee "$OWNER" >/dev/null 2>&1 ) && echo "✅ $SLUG#$NUM assignee=$OWNER"
gh project item-add $PROJ --owner $OWNER --url "https://github.com/$OWNER/$SLUG/issues/$NUM" >/dev/null 2>&1 || true
ITEM=$(gh project item-list $PROJ --owner $OWNER --format json --limit 400 2>/dev/null | python3 -c "
import json,sys
slug='$SLUG'; num=int('$NUM')
for i in json.load(sys.stdin)['items']:
    c=i.get('content',{})
    if c.get('number')==num and c.get('repository','').endswith(slug): print(i['id']); break
")
[ -n "$ITEM" ] && gh project item-edit --id "$ITEM" --project-id "$PROJ_ID" --field-id "$FID" --single-select-option-id "$OPT" >/dev/null 2>&1 \
  && echo "✅ $SLUG#$NUM status=$STATE" || echo "⚠️ ตั้ง status ไม่สำเร็จ ($SLUG#$NUM)"
