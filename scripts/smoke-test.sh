#!/usr/bin/env bash
set -euo pipefail

base_url="${1:-http://localhost:8080}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for JSON validation. Please install jq and retry."
  exit 1
fi

post_payload="$(jq -nc '{accountId: "1001", type: "DEBIT", amount: 19.99, currency: "USD", description: "Smoke test"}')"

root_response="$(curl -fsS "$base_url/")"
list_response="$(curl -fsS "$base_url/transactions")"
created_response="$(curl -fsS -X POST "$base_url/transactions" \
  -H 'Content-Type: application/json' \
  -d "$post_payload")"
created_id="$(jq -r '.id // empty' <<<"$created_response")"

if [[ "$root_response" != *"quarkus transactions service is running"* ]]; then
  echo "Root endpoint check failed"
  exit 1
fi

if ! jq -e 'arrays and any(.[]; .id == "t-1001")' >/dev/null <<<"$list_response"; then
  echo "Transactions endpoint check failed: expected transaction 't-1001'"
  exit 1
fi

if [[ -z "$created_id" ]]; then
  echo "Transactions POST check failed: response did not include an id"
  exit 1
fi

lookup_response="$(curl -fsS "$base_url/transactions/$created_id")"
if ! jq -e --arg id "$created_id" '.id == $id and .accountId == "1001"' >/dev/null <<<"$lookup_response"; then
  echo "Transaction lookup check failed for id $created_id"
  exit 1
fi

echo "Smoke test passed for $base_url/transactions"
