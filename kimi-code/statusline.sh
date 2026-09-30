#!/bin/bash
# Kimi Code status line (fast path <100ms):
#   base info from the stdin snapshot + managed quota from cache.
# Slow quota fetching (curl ~1-2s) runs in a detached background process,
# because kimi kills the status line command after 300ms and discards output.
set -u

HOME_DIR="${KIMI_CODE_HOME:-$HOME/.kimi-code}"
CACHE_DIR="$HOME_DIR/.cache"
CACHE_FILE="$CACHE_DIR/statusline-quota.json"
FETCH_LOCK="$CACHE_DIR/statusline-quota.fetch.lock"
CRED_FILE=$(ls "$HOME_DIR"/credentials/kimi-code-*.json 2>/dev/null | head -1)

REGION=$(cat "$HOME_DIR/region" 2>/dev/null || echo "mainland-cn")
case "$REGION" in
  global)
    OAUTH_HOST="${KIMI_CODE_OAUTH_HOST:-https://auth.kimi.ai}"
    BASE="${KIMI_CODE_BASE_URL:-https://api.kimi.ai/coding/v1}"
    ;;
  *)
    OAUTH_HOST="${KIMI_CODE_OAUTH_HOST:-https://www.kimi.com}"
    BASE="${KIMI_CODE_BASE_URL:-https://api.kimi.com/coding/v1}"
    ;;
esac
CLIENT_ID="17e5f671-d194-4dfb-9706-5516cb48c098"
CACHE_TTL=60

# --- fetch quota in the background and write the cache ---
# kimi kills the status line command (and its whole process group) after 300ms;
# a SIGKILLed fetcher would leave the lock behind forever, so stale locks are stolen.
fetch_quota() {
  mkdir -p "$CACHE_DIR" 2>/dev/null
  if ! mkdir "$FETCH_LOCK" 2>/dev/null; then
    NOW_TS=$(date +%s)
    LOCK_TS=$NOW_TS
    if [ -f "$FETCH_LOCK/started" ]; then
      LOCK_TS=$(cat "$FETCH_LOCK/started" 2>/dev/null || echo 0)
    else
      LOCK_TS=$(stat -f %m "$FETCH_LOCK" 2>/dev/null || echo 0)
    fi
    if [ $((NOW_TS - LOCK_TS)) -gt 120 ]; then
      rm -rf "$FETCH_LOCK"
    else
      return 0   # another fetcher is genuinely running
    fi
    mkdir "$FETCH_LOCK" 2>/dev/null || return 0
  fi
  (
    trap 'rm -rf "$FETCH_LOCK"' EXIT
    date +%s > "$FETCH_LOCK/started"
    TOKEN=$(python3 - "$CRED_FILE" <<'PY'
import json, sys, time
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
if d.get("expires_at", 0) - time.time() > 120:
    print(d.get("access_token", ""))
PY
)
    if [ -z "${TOKEN:-}" ]; then
      REFRESH=$(python3 - "$CRED_FILE" <<'PY'
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("refresh_token", ""))
except Exception:
    pass
PY
)
      RESP=$(curl -sS -m 10 -X POST "$OAUTH_HOST/api/oauth/token" \
        -H "Content-Type: application/x-www-form-urlencoded" -H "Accept: application/json" \
        --data-urlencode "grant_type=refresh_token" \
        --data-urlencode "client_id=$CLIENT_ID" \
        --data-urlencode "refresh_token=$REFRESH" 2>/dev/null)
      TOKEN=$(python3 - "$CRED_FILE" "$RESP" <<'PY'
import json, sys, time, tempfile, os
path, resp = sys.argv[1], sys.argv[2]
try:
    p = json.loads(resp)
except Exception:
    sys.exit(1)
if "access_token" not in p:
    sys.exit(1)
try:
    old = json.load(open(path))
except Exception:
    old = {}
new = {
    "access_token": p["access_token"],
    "refresh_token": p.get("refresh_token", old.get("refresh_token", "")),
    "expires_at": int(time.time()) + int(p.get("expires_in", 900)),
    "scope": p.get("scope", old.get("scope", "")),
    "token_type": p.get("token_type", "Bearer"),
    "expires_in": int(p.get("expires_in", 900)),
}
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, "w") as f:
    json.dump(new, f, indent=2)
os.chmod(tmp, 0o600)
try:
    os.replace(tmp, path)
except Exception:
    os.unlink(tmp)
    sys.exit(1)
print(new["access_token"])
PY
)
    fi

    if [ -n "${TOKEN:-}" ]; then
      RAW=$(curl -sS -m 10 "$BASE/usages" \
        -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" 2>/dev/null)
      if [ -n "$RAW" ] && printf '%s' "$RAW" | grep -q '"usages"'; then
        printf '%s' "$RAW" > "$CACHE_FILE.tmp.$$" && mv "$CACHE_FILE.tmp.$$" "$CACHE_FILE"
        # append a consumption sample for burn-rate estimates
        RAW="$RAW" python3 - "$CACHE_DIR/statusline-quota-history.json" <<'PY'
import json, sys, time, os, tempfile
path = sys.argv[1]
try:
    d = json.loads(os.environ.get("RAW") or "")
except Exception:
    sys.exit(0)
lim = (d.get("limits") or [{}])[0]
det = lim.get("detail", {})
try:
    w_used = float(det.get("used", 0) or 0)
    w_lim = float(det.get("limit", 0) or 0)
except Exception:
    sys.exit(0)
ratio = ((d.get("usages") or {}).get("limit_month_total") or {}).get("used_ratio")
try:
    m_ratio = float(ratio)
except Exception:
    m_ratio = None
now = time.time()
try:
    hist = json.load(open(path))
    if not isinstance(hist, list):
        hist = []
except Exception:
    hist = []
# a reset zeroes the counters; drop pre-reset samples so the rate stays valid
if hist:
    last = hist[-1]
    if w_used < last[1] * 0.5 or (m_ratio is not None and last[2] is not None and m_ratio < last[2] * 0.5):
        hist = []
hist.append([int(now), w_used, m_ratio])
hist = [h for h in hist if isinstance(h, list) and len(h) == 3 and now - h[0] < 7 * 24 * 3600]
hist = hist[-1000:]
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".")
with os.fdopen(fd, "w") as f:
    json.dump(hist, f)
os.replace(tmp, path)
PY
      fi
    fi
    rmdir "$FETCH_LOCK" 2>/dev/null
  ) >/dev/null 2>&1 &
}

# --- read cache; if stale/missing, kick a background fetch ---
NOW=$(date +%s)
QJSON=""
CACHE_FRESH=0
if [ -f "$CACHE_FILE" ]; then
  QMTIME=$(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
  QJSON=$(cat "$CACHE_FILE" 2>/dev/null)
  if [ $((NOW - QMTIME)) -lt $CACHE_TTL ] && [ -n "$QJSON" ]; then
    CACHE_FRESH=1
  fi
fi
if [ "$CACHE_FRESH" != "1" ] && [ -n "$CRED_FILE" ]; then
  fetch_quota
fi

SNAP=$(cat)

# --- render the whole line in one python pass ---
SNAP="$SNAP" QJSON="$QJSON" HIST_FILE="$CACHE_DIR/statusline-quota-history.json" python3 - <<'PY'
import json, os, sys, time
from datetime import datetime, timezone

def load(name):
    try:
        return json.loads(os.environ.get(name) or "{}")
    except Exception:
        return {}

s = load("SNAP")
q = load("QJSON")

# Tokyo Night-ish palette
C_RED = "\033[38;2;247;118;142m"
C_YELLOW = "\033[38;2;224;175;104m"
C_GREEN = "\033[38;2;158;206;106m"
C_CYAN = "\033[38;2;125;207;255m"
C_PURPLE = "\033[38;2;187;154;247m"
C_GRAY = "\033[38;2;110;120;150m"
C_RESET = "\033[0m"

def pick(src, *ks):
    for k in ks:
        v = src.get(k)
        if v:
            return str(v)
    return ""

def color_by(ratio, invert=False):
    # ratio: 0..1 (usage); invert=True means it's a "remaining" fraction
    v = 1 - ratio if invert else ratio
    if v > 0.8:
        return C_RED
    if v > 0.6:
        return C_YELLOW
    return C_GREEN

def time_left(iso):
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        secs = int((dt - datetime.now(timezone.utc)).total_seconds())
        return fmt_duration(secs)
    except Exception:
        return ""

def fmt_duration(secs):
    if secs <= 0:
        return "now"
    d, rem = divmod(secs, 86400)
    h, rem = divmod(rem, 3600)
    m = rem // 60
    if d > 0:
        return "%dd%dh" % (d, h)
    if h > 0:
        return "%dh%dm" % (h, m)
    return "%dm" % m

def burn_rate(idx):
    """Units per second from history samples, or None if not enough data."""
    try:
        hist = json.load(open(os.environ["HIST_FILE"]))
    except Exception:
        return None
    if not isinstance(hist, list) or len(hist) < 2:
        return None
    now = time.time()
    recent = [h for h in hist if isinstance(h, list) and len(h) == 3
              and h[idx] is not None and now - h[0] < 7 * 24 * 3600]
    if len(recent) < 2:
        recent = [h for h in hist if isinstance(h, list) and len(h) == 3 and h[idx] is not None]
    if len(recent) < 2:
        return None
    t0, v0 = recent[0][0], recent[0][idx]
    t1, v1 = recent[-1][0], recent[-1][idx]
    dt = t1 - t0
    if dt < 600:
        return None
    rate = (v1 - v0) / dt
    return rate if rate > 0 else None

def secs_until(iso):
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        return int((dt - datetime.now(timezone.utc)).total_seconds())
    except Exception:
        return None

parts = []

model = pick(s, "model")
if model:
    parts.append(C_CYAN + model + C_RESET)

mode = pick(s, "permissionMode")
if mode:
    parts.append(C_GRAY + mode + C_RESET)

cwd = s.get("cwd") or os.getcwd()
cwd_name = os.path.basename(cwd.rstrip("/")) or cwd
parent = os.path.basename(os.path.dirname(cwd.rstrip("/")))
if parent:
    parts.append(C_GRAY + parent + "/" + C_PURPLE + cwd_name + C_RESET)
else:
    parts.append(C_PURPLE + cwd_name + C_RESET)

branch = pick(s, "gitBranch")
if branch:
    parts.append(C_GRAY + "git:" + C_CYAN + branch + C_RESET)

ct, mt = s.get("contextTokens"), s.get("maxContextTokens")
if isinstance(ct, int) and isinstance(mt, int) and mt > 0:
    pct = int(round(100 * ct / mt))
    parts.append(color_by(ct / mt) + "ctx %d%%" % pct + C_RESET)

quota_parts = []
limits = q.get("limits") or []
lim = limits[0] if limits else None
det = (lim or {}).get("detail", {})
rem, tot = det.get("remaining"), det.get("limit")
win = (lim or {}).get("window", {})
mins = win.get("duration") if win.get("timeUnit") == "TIME_UNIT_MINUTE" else None
label = ("%dh" % (mins // 60)) if isinstance(mins, int) and mins >= 60 else "lim"
if rem is not None and tot:
    try:
        frac = float(rem) / float(tot)
    except Exception:
        frac = 1.0
    txt = C_GRAY + label + " " + C_RESET + color_by(frac, invert=True) + "%s/%s" % (rem, tot) + C_RESET
    left = time_left(det.get("resetTime", ""))
    if left:
        txt += C_GRAY + " (reset %s" % left + C_RESET
        # at the current burn rate, will the window run out before it resets?
        rate = burn_rate(1)
        reset_secs = secs_until(det.get("resetTime", ""))
        if rate and reset_secs:
            left_secs = float(rem) / rate
            if left_secs < reset_secs:
                txt += C_GRAY + ", " + C_RED + "~%s" % fmt_duration(int(left_secs)) + C_GRAY
        txt += ")"
    quota_parts.append(txt)

us = q.get("usages") or {}
mt_entry = us.get("limit_month_total")
if mt_entry:
    ratio = mt_entry.get("used_ratio")
    txt = C_GRAY + "month " + C_RESET
    if ratio is not None:
        txt += color_by(ratio) + "%d%%" % int(round(ratio * 100)) + C_RESET
    else:
        txt += "?"
    left = time_left(mt_entry.get("reset_time", ""))
    if left:
        txt += C_GRAY + " (reset %s" % left + C_RESET
        rate = burn_rate(2)
        reset_secs = secs_until(mt_entry.get("reset_time", ""))
        if rate and reset_secs and ratio is not None:
            left_secs = (1.0 - ratio) / rate
            if left_secs < reset_secs:
                txt += C_GRAY + ", " + C_RED + "~%s" % fmt_duration(int(left_secs)) + C_GRAY
        txt += ")"
    quota_parts.append(txt)

if quota_parts:
    parts.append(C_GRAY + "|" + C_RESET)
    parts.extend(quota_parts)

print("  ".join(parts))
PY
