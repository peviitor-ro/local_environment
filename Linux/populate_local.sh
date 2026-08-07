#!/bin/bash
#########################################################################
#  populate_local.sh
#  Syncs the local Solr cores (job / company) from the production Solr
#  (solr.peviitor.ro). Replaces what migration.jmx / firme.jmx do,
#  but uses curl + python3 instead of JMeter.
#
#  Usage:
#    ./populate_local.sh
#
#  Requirements: curl, python3 (already present in this environment).
#########################################################################

set -euo pipefail

# --- Config ------------------------------------------------------------
PROD_BASE="https://solr.peviitor.ro/solr"
LOCAL_BASE="http://localhost:8983/solr"

PROD_USER="${PROD_USER:-solr}"
PROD_PASS="${PROD_PASS:-SolrRocks}"

LOCAL_USER="${LOCAL_USER:-ale}"
LOCAL_PASS="${LOCAL_PASS:-Aleeceamaijmkera123!}"

# prod job fields that we replicate locally (matches prod /solr/job/select)
JOB_FL="url,title,company,company_name,cif,location,tags,workmode,date,status,job_title,city,country,county,remote,salary,source,workplaceType"

PAGE_SIZE=1000

# --- Helpers -----------------------------------------------------------
log()  { echo "[$(date '+%H:%M:%S')] $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

# Strip Solr-internal fields (_version_, _root_) from a docs JSON array.
strip_internal() {
  python3 -c '
import sys, json
docs = json.load(sys.stdin)
for d in docs:
    d.pop("_version_", None)
    d.pop("_root_", None)
json.dump(docs, sys.stdout)
'
}

# Sync one core: wipe local, then paginate prod and push to local.
sync_core() {
  local core="$1"
  local fl="$2"   # empty => all stored fields

  log "==> Syncing core '$core'"

  # 1. wipe the local core
  local wipe
  wipe=$(curl -s -u "$LOCAL_USER:$LOCAL_PASS" -X POST \
    -H 'Content-Type: application/json' \
    --data '{"delete":{"query":"*:*"}}' \
    "$LOCAL_BASE/$core/update?commit=true" || true)
  echo "$wipe" | grep -q '"status":0' || die "failed to wipe local core '$core': $wipe"

  # 2. read total count from prod
  local total
  total=$(curl -s -u "$PROD_USER:$PROD_PASS" \
    "$PROD_BASE/$core/select?q=*:*&rows=0&wt=json" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["response"]["numFound"])')
  log "    prod has $total documents"

  # 3. paginate prod and post to local
  local start=0 sent=0
  while [ "$start" -lt "$total" ]; do
    local docs
    docs=$(curl -s -u "$PROD_USER:$PROD_PASS" \
      "$PROD_BASE/$core/select?q=*:*&rows=$PAGE_SIZE&start=$start&wt=json${fl:+&fl=$fl}" \
      | python3 -c 'import sys,json; print(json.dumps(json.load(sys.stdin)["response"]["docs"]))')

    # stop if prod returned nothing (avoid infinite loop)
    [ -n "$docs" ] && [ "$docs" != "[]" ] || break

    docs=$(echo "$docs" | strip_internal)

    local out
    out=$(echo "$docs" | strip_internal | curl -s -u "$LOCAL_USER:$LOCAL_PASS" -X POST \
      -H 'Content-Type: application/json' \
      --data-binary @- \
      "$LOCAL_BASE/$core/update?commitWithin=1000&overwrite=true&wt=json")
    echo "$out" | grep -q '"status":0' || die "failed POSTing page start=$start: $out"

    sent=$((sent + PAGE_SIZE))
    log "    pushed $sent / $total (start=$start)"
    start=$((start + PAGE_SIZE))
  done

  # 4. final commit
  curl -s -u "$LOCAL_USER:$LOCAL_PASS" -X POST \
    -H 'Content-Type: application/json' \
    --data '{"commit":{}}' \
    "$LOCAL_BASE/$core/update" >/dev/null

  # 5. verify count
  local local_count
  local_count=$(curl -s -u "$LOCAL_USER:$LOCAL_PASS" \
    "$LOCAL_BASE/$core/select?q=*:*&rows=0&wt=json" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["response"]["numFound"])')
  log "    DONE: local '$core' has $local_count documents"
}

# --- Run ---------------------------------------------------------------
sync_core "job" "$JOB_FL"
sync_core "company" ""

log "==> All cores synced."
