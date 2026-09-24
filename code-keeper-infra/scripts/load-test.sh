#!/usr/bin/env bash
#
# load-test.sh — simple concurrent load generator (no external deps).
#
# Usage:
#   ./load-test.sh <url> [requests] [concurrency] [bearer-token]
#
# Example:
#   ./load-test.sh "https://<alb>/" 500 50
#   TOKEN=... ./load-test.sh "https://<alb>/api/movies" 500 50 "$TOKEN"
#
set -euo pipefail

URL="${1:?usage: $0 <url> [requests] [concurrency] [token]}"
REQUESTS="${2:-500}"
CONCURRENCY="${3:-50}"
TOKEN="${4:-${TOKEN:-}}"

python3 - "$URL" "$REQUESTS" "$CONCURRENCY" "$TOKEN" <<'PY'
import collections
import concurrent.futures
import ssl
import sys
import time
import urllib.error
import urllib.request

url, requests_n, concurrency, token = (
    sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4],
)

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE


def one(_):
    req = urllib.request.Request(url)
    if token:
        req.add_header("Authorization", "Bearer " + token)
    start = time.time()
    try:
        with urllib.request.urlopen(req, timeout=20, context=ctx) as resp:
            resp.read()
            code = resp.status
    except urllib.error.HTTPError as exc:
        code = exc.code
    except Exception as exc:  # noqa: BLE001
        code = type(exc).__name__
    return code, time.time() - start


started = time.time()
with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as pool:
    results = list(pool.map(one, range(requests_n)))
elapsed = time.time() - started

codes = collections.Counter(code for code, _ in results)
latencies = sorted(d for _, d in results)
avg = sum(latencies) / len(latencies)
p95 = latencies[max(0, int(len(latencies) * 0.95) - 1)]

print(f"url={url}")
print(f"requests={requests_n} concurrency={concurrency} elapsed={elapsed:.1f}s "
      f"rps={requests_n / elapsed:.1f}")
print("status:", dict(codes))
print(f"avg={avg * 1000:.0f}ms p95={p95 * 1000:.0f}ms")
PY
