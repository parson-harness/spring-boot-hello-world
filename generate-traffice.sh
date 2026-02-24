#!/usr/bin/env bash
# generate-traffic.sh
#
# Generate HTTP traffic to a Kubernetes Service (type=LoadBalancer) by discovering its ELB.
# Defaults match your Spring Boot app (Service: parson-java-one-svc in ns: default).
#
# Usage examples:
#   # Quick burst of 200 requests to "/"
#   ./generate-traffic.sh --burst 200
#
#   # Steady load: 60 seconds at 20 RPS, 4 concurrent workers, path "/"
#   ./generate-traffic.sh --duration 60 --rps 20 --concurrency 4 --path /
#
#   # Target a different service/namespace
#   ./generate-traffic.sh --namespace default --service my-svc --burst 100
#
#   # Skip discovery and hit a known URL directly
#   ./generate-traffic.sh --url http://my-app-123.elb.amazonaws.com/ --burst 100
#
# Options:
#   --namespace <ns>        (default: default)
#   --service   <name>      (default: parson-java-one-svc)
#   --path      <path>      (default: /)
#   --url       <http(s)://..>  (optional, bypasses discovery)
#   --burst     <N>         (send N requests as fast as possible)
#   --duration  <seconds>   (steady mode: how long to run)
#   --rps       <number>    (steady mode: requests per second total across workers)
#   --concurrency <N>       (steady mode: number of worker loops; default 4)
#   --method    <GET|POST|...> (default: GET)
#   --header    "Name: Value"  (can repeat)
#   --data      '<body>'    (for POST/PUT/PATCH)
#   --insecure               (allow insecure TLS)
#   --verbose                (print each HTTP code as it arrives)
#
set -euo pipefail

NS="dev"
SVC="spring-boot-hello-world-svc"
PATH_PART="/"
TARGET_URL=""
BURST=0
DURATION=0
RPS=0
CONCURRENCY=4
METHOD="GET"
DATA=""
INSECURE=0
VERBOSE=0
declare -a HEADERS

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace) NS="$2"; shift 2;;
    --service) SVC="$2"; shift 2;;
    --path) PATH_PART="$2"; shift 2;;
    --url) TARGET_URL="$2"; shift 2;;
    --burst) BURST="$2"; shift 2;;
    --duration) DURATION="$2"; shift 2;;
    --rps) RPS="$2"; shift 2;;
    --concurrency) CONCURRENCY="$2"; shift 2;;
    --method) METHOD="$2"; shift 2;;
    --header) HEADERS+=("$2"); shift 2;;
    --data) DATA="$2"; shift 2;;
    --insecure) INSECURE=1; shift 1;;
    --verbose) VERBOSE=1; shift 1;;
    -h|--help)
      sed -n '1,120p' "$0"; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need kubectl
need awk
need xargs
need grep
need sed
need date
need mktemp
need curl

make_url() {
  local host="$1"
  local port="$2"
  local path="$3"
  [[ "$path" != /* ]] && path="/$path"
  local scheme="http"
  [[ "$port" == "443" ]] && scheme="https"
  if [[ "$port" == "80" || "$port" == "443" ]]; then
    echo "${scheme}://${host}${path}"
  else
    echo "${scheme}://${host}:${port}${path}"
  fi
}

discover_url() {
  local ns="$1" svc="$2" path="$3"
  echo "🔎 Discovering ELB for Service ${ns}/${svc} ..."
  local json
  if ! json="$(kubectl -n "$ns" get svc "$svc" -o json)"; then
    echo "❌ Unable to get service ${ns}/${svc}" >&2; exit 1
  fi

  local host ip port
  # Try hostname first, then IP
  host="$(printf '%s' "$json" | sed -n 's/.*"hostname"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)"
  ip="$(printf '%s' "$json" | sed -n 's/.*"ip"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)"
  port="$(printf '%s' "$json" | sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1 || echo 80)"

  local host_or_ip="${host:-$ip}"
  if [[ -z "$host_or_ip" ]]; then
    echo "❌ Service ${ns}/${svc} does not have a LoadBalancer ingress yet." >&2
    exit 1
  fi

  make_url "$host_or_ip" "$port" "$path"
}

if [[ -z "$TARGET_URL" ]]; then
  TARGET_URL="$(discover_url "$NS" "$SVC" "$PATH_PART")"
fi

echo "🎯 Target: $TARGET_URL"
TMP_CODES="$(mktemp)"
trap 'rm -f "$TMP_CODES"' EXIT

curl_common=(-s -o /dev/null -w "%{http_code}\n" -X "$METHOD")
for h in "${HEADERS[@]}"; do curl_common+=(-H "$h"); done
[[ -n "$DATA" ]] && curl_common+=(--data "$DATA")
(( INSECURE == 1 )) && curl_common+=(-k)

do_request() {
  local code
  code="$(curl "${curl_common[@]}" "$TARGET_URL" || echo "000")"
  echo "$code" >> "$TMP_CODES"
  (( VERBOSE == 1 )) && echo "$code"
}

if (( BURST > 0 )); then
  echo "⚡ Burst mode: ${BURST} requests as fast as possible..."
  # Use xargs for some parallelism
  seq "$BURST" | xargs -n1 -P "$(min() { echo $(( $1 < $2 ? $1 : $2 )); }; min "$CONCURRENCY" 16)" -I{} bash -c 'do_request' _ 2>/dev/null
else
  if (( DURATION <= 0 || RPS <= 0 )); then
    echo "❌ In steady mode, provide both --duration and --rps (or use --burst)." >&2
    exit 2
  fi

  echo "🚿 Steady mode: ${DURATION}s @ ${RPS} RPS across ${CONCURRENCY} workers"
  # Per-worker RPS (allow fractional)
  per_rps=$(awk -v r="$RPS" -v c="$CONCURRENCY" 'BEGIN{printf("%.6f", r/c)}')
  # Sleep between requests per worker
  per_sleep=$(awk -v pr="$per_rps" 'BEGIN{ if (pr<=0) print "0"; else printf("%.6f", 1.0/pr) }')

  end_time=$(( $(date +%s) + DURATION ))

  worker() {
    local sleep_secs="$1"
    while (( $(date +%s) < end_time )); do
      do_request
      # shellcheck disable=SC2039
      sleep "$sleep_secs"
    done
  }

  # Launch workers
  pids=()
  for _ in $(seq 1 "$CONCURRENCY"); do
    worker "$per_sleep" &
    pids+=($!)
  done
  # Wait for completion
  for p in "${pids[@]}"; do wait "$p"; done
fi

echo ""
echo "📊 Status code summary:"
# shellcheck disable=SC2002
cat "$TMP_CODES" | sort | uniq -c | sed 's/^/  /'

TOTAL_REQ=$(wc -l < "$TMP_CODES" | awk '{print $1}')
SUCCESS=$(grep -E '^(200|201|202|204)$' "$TMP_CODES" | wc -l | awk '{print $1}')
echo ""
echo "Total: $TOTAL_REQ   Success(2xx): $SUCCESS   Errors: $(( TOTAL_REQ - SUCCESS ))"
echo ""
echo "✅ Done. Open Grafana → Explore and run, for example:"
echo "  sum(rate(http_server_requests_seconds_count[5m]))"
echo "  sum by (uri) (rate(http_server_requests_seconds_count[5m]))"
