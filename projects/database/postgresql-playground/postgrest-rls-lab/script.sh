b64url() {
  printf '%s' "$1" | base64 -w 0 | tr '+/' '-_' | tr -d '='
}

make_jwt() {
  workspace="$1"
  header=$(b64url '{"alg":"HS256","typ":"JWT"}')
  payload=$(b64url "{\"role\":\"tenant_user\",\"workspace_id\":\"${workspace}\",\"exp\":$(( $(date +%s) + 3600 ))}")
  unsigned="${header}.${payload}"
  signature=$(printf '%s' "$unsigned" | \
    openssl dgst -sha256 -mac HMAC -macopt "hexkey:${JWT_SECRET}" -binary | \
    base64 -w 0 | tr '+/' '-_' | tr -d '=')
  printf '%s.%s' "$unsigned" "$signature"
}

export ALPHA_JWT="$(make_jwt ws_alpha)"
export BETA_JWT="$(make_jwt ws_beta)"

if [ -f postgrest.pid ] && kill -0 "$(cat postgrest.pid)" 2>/dev/null; then
  kill "$(cat postgrest.pid)"
  sleep 2
fi

postgrest postgrest.conf > postgrest.log 2>&1 &
echo $! > postgrest.pid

until curl -fsS http://localhost:3000/ >/dev/null; do
  sleep 2
done

curl -sS http://localhost:3000/
