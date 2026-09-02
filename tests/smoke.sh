#!/usr/bin/env bash
set -euo pipefail
API_URL="${API_URL:-http://localhost:3000}"

for _ in $(seq 1 30); do
  curl -fsS "$API_URL/" >/dev/null && break
  sleep 1
done

register() {
  curl -fsS "$API_URL/rpc/register" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$1\",\"password\":\"correct-horse-battery\"}"
}

token_a="$(register alice@example.com | sed -E 's/.*"token":"([^"]+)".*/\1/')"
token_b="$(register bob@example.com | sed -E 's/.*"token":"([^"]+)".*/\1/')"

curl -fsS "$API_URL/rpc/create_project_with_first_task" \
  -H "Authorization: Bearer $token_a" -H 'Content-Type: application/json' \
  -d '{"name":"Alice project","task_title":"Private task"}' >/dev/null

alice_projects="$(curl -fsS "$API_URL/projects" -H "Authorization: Bearer $token_a")"
bob_projects="$(curl -fsS "$API_URL/projects" -H "Authorization: Bearer $token_b")"
[[ "$alice_projects" == *"Alice project"* ]]
[[ "$bob_projects" == "[]" ]]
echo 'Smoke test passed: auth, RPC, and cross-user RLS isolation work.'
