#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-}"
[[ -n "$BASE_URL" ]] || { echo "Usage: $0 https://portal.example.com" >&2; exit 2; }
BASE_URL="${BASE_URL%/}"
CURL=(curl --silent --show-error --location --max-time 30)

expect_status() {
  local path="$1" expected="$2" actual
  actual="$(curl --silent --show-error --output /dev/null --max-time 30 --write-out '%{http_code}' "$BASE_URL$path")"
  [[ "$actual" =~ $expected ]] || { echo "FAIL $path returned $actual; expected $expected" >&2; exit 1; }
  echo "OK   $path -> $actual"
}

health="$(${CURL[@]} "$BASE_URL/index.cfm/healthz")"
[[ "$health" == *'"OK":true'* || "$health" == *'"ok":true'* ]] || { echo "FAIL /index.cfm/healthz did not return a healthy JSON response: $health" >&2; exit 1; }
echo "OK   /index.cfm/healthz"

login="$(${CURL[@]} "$BASE_URL/index.cfm/login")"
[[ "$login" == *"Sign in"* ]] || { echo "FAIL /index.cfm/login did not render the sign-in page." >&2; exit 1; }
echo "OK   /index.cfm/login"

expect_status "/static/css/app.css" '^200$'
expect_status "/index.cfm/training-tracker/" '^(200|30[1278])$'
expect_status "/Application.cfc" '^(403|404)$'
expect_status "/data/logicore.mv.db" '^(403|404)$'
expect_status "/config/serial_rules.json" '^(403|404)$'
expect_status "/services/AuthService.cfc" '^(403|404)$'
expect_status "/tests/billing_parity.cfm" '^(403|404)$'

echo "Deployment checks passed for $BASE_URL"

