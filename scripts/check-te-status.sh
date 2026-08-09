#!/bin/bash
# ============================================================
# Check ThousandEyes test status via API (no browser login required)
# ============================================================
# Why this exists: attendees on a shared ThousandEyes account can't log
# into app.thousandeyes.com (that requires YOUR Cisco SSO session). But
# TE_BEARER_TOKEN is a bearer token, not an SSO session — it works from
# any terminal that has it, without ever visiting the browser UI. This
# script polls the TE API directly and prints each test's live status,
# filtered to your own tests by TEST_PREFIX.
#
# Endpoints used (ThousandEyes API v7):
#   GET /v7/tests                          - list tests, filter by name prefix
#   GET /v7/test-results/{testId}/http-server?window=10m
#                                           - most recent round(s) for each test
#
# Required env vars:
#   TE_BEARER_TOKEN  - ThousandEyes OAuth Bearer token
#   TEST_PREFIX      - Your test name prefix (e.g. your-name), set in Module 1
#                       (falls back to AGENT_HOSTNAME if TEST_PREFIX is unset)
#
# Usage:
#   bash scripts/check-te-status.sh            # one-shot status check
#   bash scripts/check-te-status.sh --watch    # refresh every 15s (Ctrl+C to stop)
# ============================================================

set -e

: "${TE_BEARER_TOKEN:?ERROR: TE_BEARER_TOKEN is required}"
: "${TEST_PREFIX:=${AGENT_HOSTNAME:-}}"
: "${TEST_PREFIX:?ERROR: TEST_PREFIX (or AGENT_HOSTNAME) is required}"

WATCH=false
[ "${1:-}" = "--watch" ] && WATCH=true

check_once() {
  python3 - "${TE_BEARER_TOKEN}" "${TEST_PREFIX}" << 'PYEOF'
import json, sys, urllib.request, urllib.error
from datetime import datetime, timezone

TOKEN, PREFIX = sys.argv[1], sys.argv[2]
HDRS = {"Authorization": f"Bearer {TOKEN}"}
API = "https://api.thousandeyes.com/v7"

GREEN = "\033[0;32m"
RED = "\033[0;31m"
YELLOW = "\033[0;33m"
BOLD = "\033[1m"
NC = "\033[0m"


def api_get(path):
    req = urllib.request.Request(f"{API}{path}", headers=HDRS, method="GET")
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        print(f"{RED}ERROR {e.code} calling {path}: {e.read().decode()[:300]}{NC}",
              file=sys.stderr)
        return None
    except urllib.error.URLError as e:
        print(f"{RED}ERROR connecting to ThousandEyes API: {e}{NC}", file=sys.stderr)
        return None


needle = f"[{PREFIX}]"
tests_resp = api_get("/tests")
if tests_resp is None:
    sys.exit(1)

tests = [t for t in tests_resp.get("tests", [])
         if t.get("testName", "").startswith(needle)]

if not tests:
    print(f"No tests found with prefix '{needle}'. "
          f"Did Module 1's deploy.sh finish Step 4 (ThousandEyes tests)?")
    sys.exit(0)

print(f"{BOLD}ThousandEyes status — prefix {needle}  "
      f"({datetime.now().strftime('%H:%M:%S')}){NC}")
print("-" * 72)

up_count = 0
down_count = 0

for t in sorted(tests, key=lambda t: t.get("testName", "")):
    test_id = t["testId"]
    name = t["testName"].replace(needle, "").strip(" -")
    result = api_get(f"/test-results/{test_id}/http-server?window=10m")
    if result is None:
        print(f"  {YELLOW}? {name} — could not fetch results{NC}")
        continue

    rounds = result.get("results", [])
    if not rounds:
        print(f"  {YELLOW}? {name:<32} no data yet (agent may still be registering){NC}")
        continue

    latest = sorted(rounds, key=lambda r: r.get("roundId", 0))[-1]
    error_type = (latest.get("errorType") or "").strip()
    is_down = bool(error_type) and error_type.lower() != "none"
    response_code = latest.get("responseCode")
    response_time = latest.get("responseTime")
    error_details = latest.get("errorDetails") or ""
    date = latest.get("date", "")

    if is_down:
        down_count += 1
        detail = error_details or error_type
        print(f"  {RED}\u2717 DOWN{NC}  {name:<32} {detail}  (as of {date})")
    else:
        up_count += 1
        detail = f"{response_code} in {response_time}ms" if response_code else "OK"
        print(f"  {GREEN}\u2713 UP  {NC}  {name:<32} {detail}  (as of {date})")

print("-" * 72)
summary_color = GREEN if down_count == 0 else RED
print(f"{summary_color}{up_count} up, {down_count} down{NC} out of {len(tests)} tests")
PYEOF
}

if [ "${WATCH}" = true ]; then
  while true; do
    clear
    check_once
    echo ""
    echo "Refreshing every 15s — Ctrl+C to stop"
    sleep 15
  done
else
  check_once
fi
