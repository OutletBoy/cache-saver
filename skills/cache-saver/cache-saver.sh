#!/usr/bin/env bash
# Cache Saver (Cash Saver) for Claude Code: wakes Claude before its prompt
# cache goes cold, and switches itself off once the nudges have cost about as
# much as one cold restart would.
#
# Claude runs this as a BACKGROUND task. It watches the chat's transcript
# file and exits N minutes after the last request to Claude STARTED. Its LAST LINE
# tells Claude what to do next (reply and start it again, or stay stopped).
#
# Usage: bash cache-saver.sh [--minutes N] [--max-nudges N] [--find-me WORD | --file PATH]
#   --minutes N     quiet time before a nudge (default 55; the cache lasts 60)
#   --max-nudges N  wake-ups in a row before it switches itself off (default 9:
#                   each nudge is two short requests, so 8 nudges plus the note cost
#                   about one cold restart; 0 = never)
#   --find-me WORD  watch the chat whose transcript contains WORD: Claude puts a fresh
#                   random word in its own command, so it always finds ITS chat, even
#                   with several chats running (recommended)
#   --file PATH     transcript to watch (default: the newest one Claude Code wrote)
#
# Exit codes: 0 = nudge (reply and start again), 3 = switched off, 2 = error,
#             4 = a newer copy took over this chat (do nothing),
#             5 = the usage limit is reached (start it again after the reset).

MINUTES=55
MAX_NUDGES=9
FILE=""
FIND=""
need() { if [ $# -lt 2 ]; then echo "cache-saver: $1 needs a value (try --help)"; exit 2; fi; }
while [ $# -gt 0 ]; do
  case "$1" in
    --minutes|--max-nudges|--file|--find-me) need "$@" ;;
  esac
  case "$1" in
    --minutes) MINUTES="$2"; shift 2 ;;
    --max-nudges) MAX_NUDGES="$2"; shift 2 ;;
    --file) FILE="$2"; shift 2 ;;
    --find-me) FIND="$2"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "cache-saver: unknown option $1 (try --help)"; exit 2 ;;
  esac
done

isnum() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; return 0; }
if ! isnum "$MINUTES" || [ "$MINUTES" -lt 1 ]; then echo "cache-saver: --minutes must be a whole number, 1 or more"; exit 2; fi
if ! isnum "$MAX_NUDGES"; then echo "cache-saver: --max-nudges must be a whole number (0 = never switch off)"; exit 2; fi

CONF="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# File modified time in epoch seconds: GNU stat (Linux, Git Bash) or BSD stat (macOS).
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

# Reading the chat's record. Every entry carries its kind and its time; nothing
# else is used. Two times matter:
#   request start -- the cache's hour restarts when a request to Claude STARTS,
#                    not when its reply ends. The request behind the newest reply
#                    went out right after the newest entry before that reply (a
#                    message, a tool result, or a background-task wake-up).
#   wake time     -- the newest entry that woke the chat: the user's message, or
#                    anything that arrived while Claude was idle (its last reply had
#                    ended its turn) -- another chat's message, a finished job, a
#                    scheduled wake-up. The kept-warm cache got used, so the count
#                    starts again: an autonomous loop saves with nobody at the
#                    keyboard. Entries in the middle of Claude's own work never
#                    count; Cache Saver's OWN wake-up is told apart by its time.
# Side-chats (subagents) and error replies are skipped; a usage-limit error (Claude
# Code writes the reset time beside it) is remembered until the next real reply. Uses node, jq or python,
# whichever is present; with none, the file's modified time stands in for both.
NODE_JS='let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{let u=0,r=0,h=0,a=0,idle=true,L=0;
for(const l of d.split("\n")){let o;try{o=JSON.parse(l)}catch(e){continue}
if(!o||typeof o!=="object"||o.isSidechain||typeof o.timestamp!=="string")continue;
const t=Math.floor(Date.parse(o.timestamp)/1000);if(!(t>0))continue;const m=(o.message&&typeof o.message==="object")?o.message:{};
if(o.type==="assistant"&&o.isApiErrorMessage===true&&o.error==="rate_limit"){const q=o.quotaLimits,z=(q&&typeof q==="object")?q.resetsAt:0;L=(Number.isInteger(z)&&z>0)?z:1;continue}
if(o.type==="user"){u=t;a=t;if(woke(o,m,idle))h=t}
else if(o.type==="assistant"&&m.usage&&m.model!=="<synthetic>"){if(u)r=u;a=t;L=0;const s=m.stop_reason;if(s)idle=(s!=="tool_use"&&s!=="pause_turn")}}
if(a)console.log((r||u||a)+" "+h+" "+L)});
function woke(o,m,idle){if(o.isCompactSummary)return false;const c=m.content;
if(Array.isArray(c)&&c.some(x=>x&&x.type==="tool_result"))return false;
if(typeof c!=="string"&&!Array.isArray(c))return false;
if(o.origin&&typeof o.origin==="object"&&o.origin.kind==="human")return true;
return idle}'
JQ_PROG='def woke($idle): if .isCompactSummary == true then false
    elif (.message | type) != "object" then false
    elif (.message.content | type) == "array" and ([.message.content[] | select(type == "object" and .type == "tool_result")] | length) > 0 then false
    elif ((.message.content | type) != "string") and ((.message.content | type) != "array") then false
    elif (.origin | type) == "object" and .origin.kind == "human" then true
    else $idle end;
  reduce (inputs | fromjson? | select(type == "object" and (.isSidechain | not) and (.timestamp | type) == "string")) as $o
  ({u: 0, r: 0, h: 0, a: 0, i: true, l: 0};
   (($o.timestamp | sub("\\.[0-9]+"; "") | fromdateiso8601?) // 0) as $t
   | if $t == 0 then .
     elif $o.type == "assistant" and $o.isApiErrorMessage == true and $o.error == "rate_limit"
       then .l = ((if ($o.quotaLimits | type) == "object" then $o.quotaLimits.resetsAt else null end) as $z
                  | if ($z | type) == "number" and $z > 0 then ($z | floor) else 1 end)
     elif $o.type == "user" then .i as $i | .u = $t | .a = $t | (if ($o | woke($i)) then .h = $t else . end)
     elif $o.type == "assistant" and ($o.message | type) == "object" and $o.message.usage != null and $o.message.model != "<synthetic>"
       then (if .u > 0 then .r = .u else . end) | .a = $t | .l = 0
            | (($o.message.stop_reason // null) as $s | if $s == null then . else .i = ($s != "tool_use" and $s != "pause_turn") end)
     else . end)
  | if .a > 0 then "\(if .r > 0 then .r elif .u > 0 then .u else .a end) \(.h) \(.l)" else empty end'
PY_PROG='import sys, json, datetime
def woke(o, m, idle):
    if o.get("isCompactSummary"):
        return False
    c = m.get("content")
    if isinstance(c, list) and any(isinstance(x, dict) and x.get("type") == "tool_result" for x in c):
        return False
    if not isinstance(c, (str, list)):
        return False
    g = o.get("origin")
    if isinstance(g, dict) and g.get("kind") == "human":
        return True
    return idle
u = r = h = a = lim = 0
idle = True
for l in sys.stdin.buffer.read().decode("utf-8", "replace").split("\n"):
    try:
        o = json.loads(l)
    except Exception:
        continue
    if not isinstance(o, dict) or o.get("isSidechain") or not isinstance(o.get("timestamp"), str):
        continue
    try:
        t = int(datetime.datetime.strptime(o["timestamp"][:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=datetime.timezone.utc).timestamp())
    except Exception:
        continue
    m = o.get("message") if isinstance(o.get("message"), dict) else {}
    if o.get("type") == "assistant" and o.get("isApiErrorMessage") is True and o.get("error") == "rate_limit":
        q = o.get("quotaLimits")
        z = q.get("resetsAt") if isinstance(q, dict) else None
        lim = z if isinstance(z, int) and not isinstance(z, bool) and z > 0 else 1
        continue
    if o.get("type") == "user":
        u = a = t
        if woke(o, m, idle):
            h = t
    elif o.get("type") == "assistant" and m.get("usage") and m.get("model") != "<synthetic>":
        r = u or r
        a = t
        lim = 0
        s = m.get("stop_reason")
        if s:
            idle = s not in ("tool_use", "pause_turn")
if a:
    print(r or u or a, h, lim)'
PARSER=""
if command -v node >/dev/null 2>&1; then PARSER=node
elif command -v jq >/dev/null 2>&1; then PARSER=jq
else
  for p in python3 python; do
    pp=$(command -v "$p" 2>/dev/null) || continue
    case "$pp" in *WindowsApps*) continue ;; esac               # the Microsoft Store stub
    if [ "$(uname)" = Darwin ] && [ "$pp" = /usr/bin/python3 ] && ! xcode-select -p >/dev/null 2>&1; then continue; fi
    PARSER="$pp"; break
  done
fi
# Test hook: force one reader (node, jq, a python path) or none (the fallback).
if [ -n "${CACHE_SAVER_PARSER:-}" ]; then PARSER="$CACHE_SAVER_PARSER"; [ "$PARSER" = none ] && PARSER=""; fi
# Prints "<request start> <human time> <limit reset or 0> p" when the record was
# read (the limit field is 1 when the reset time is unknown), or
# "<modified time> <modified time> 0 f" when it could not be (the fallback).
times() {
  local out=""
  case "$PARSER" in
    node) out=$(tail -n 2000 "$1" 2>/dev/null | node -e "$NODE_JS" 2>/dev/null) ;;
    jq) out=$(tail -n 2000 "$1" 2>/dev/null | jq -Rrn "$JQ_PROG" 2>/dev/null) ;;
    ?*) out=$(tail -n 2000 "$1" 2>/dev/null | "$PARSER" -c "$PY_PROG" 2>/dev/null) ;;
  esac
  set -- $out
  if isnum "$1" && isnum "$2"; then l=0; isnum "${3:-}" && l=$3; echo "$1 $2 $l p"; else m=$(mtime "$FILE"); [ -n "$m" ] && echo "$(( m - EARLY )) $m 0 f"; fi
}

if [ -n "$FIND" ] && [ -z "$FILE" ]; then
  if [ "${#FIND}" -lt 6 ]; then echo "cache-saver: --find-me needs a unique word of 6 or more characters"; exit 2; fi
  # Only chats written in the last 10 minutes: the command that started us is in one of them.
  matches=$(find "$CONF/projects" -maxdepth 2 -name '*.jsonl' -mmin -10 -exec grep -lF -- "$FIND" {} + 2>/dev/null)
  n=$(printf '%s' "$matches" | grep -c .)
  if [ "$n" -eq 1 ]; then FILE="$matches"
  elif [ "$n" -eq 0 ]; then echo "cache-saver: no chat contains '$FIND' yet -- start it again with a new random word"; exit 2
  else echo "cache-saver: $n chats contain '$FIND' -- start it again with a new random word"; exit 2
  fi
fi
if [ -z "$FILE" ]; then
  FILE=$(ls -t "$CONF"/projects/*/*.jsonl 2>/dev/null | head -1)
  if [ -z "$FILE" ]; then
    echo "cache-saver: no chat transcript found under $CONF/projects -- pass one with --file"
    exit 2
  fi
fi
if [ ! -f "$FILE" ]; then echo "cache-saver: file not found: $FILE"; exit 2; fi

LIMIT=$(( MINUTES * 60 ))
# Test hook: a limit in seconds, so the tests do not wait an hour.
if isnum "${CACHE_SAVER_TEST_SECONDS:-}"; then LIMIT="$CACHE_SAVER_TEST_SECONDS"; fi
# Fallback only: file changes this soon after a start or a stop are Claude's
# own restart, not someone waking the chat.
GRACE=120
if [ "$LIMIT" -lt 240 ]; then GRACE=$(( LIMIT / 2 )); fi
# A wake-up this soon after Cache Saver's own exit is its own (the task
# notification lands within seconds), not someone else waking the chat.
OWNWIN=60
if [ "$LIMIT" -lt 120 ]; then OWNWIN=$(( LIMIT / 2 )); fi
# Fallback only: the modified time is when the reply ENDED, a little after its
# request started, so the fallback counts from a bit earlier (about 3 minutes at
# the default). Early costs one slightly early nudge; late costs a full restart.
EARLY=$(( LIMIT / 20 ))

# One tiny counter file per chat:
#   "<wake-ups in a row> <switched-off time or 0> <wake-ups from outside counted
#    up to this time> <Cache Saver's own last exit>"
STATE_DIR="${CACHE_SAVER_STATE_DIR:-$CONF/cache-saver}"
mkdir -p "$STATE_DIR" 2>/dev/null
STATE="$STATE_DIR/$(basename "$FILE").state"
COUNT=0; STOPPED=0; SEEN=0; OWN=0
if [ -f "$STATE" ]; then read -r COUNT STOPPED SEEN OWN < "$STATE"; fi
COUNT=${COUNT%$'\r'}; STOPPED=${STOPPED%$'\r'}; SEEN=${SEEN%$'\r'}; OWN=${OWN%$'\r'}
isnum "$COUNT" || COUNT=0
isnum "$STOPPED" || STOPPED=0
isnum "$SEEN" || SEEN=0
isnum "$OWN" || OWN=0
[ "$STOPPED" -gt "$SEEN" ] && SEEN=$STOPPED   # a counter file from an older version
save() { printf '%s %s %s %s\n' "$COUNT" "$STOPPED" "$SEEN" "$OWN" > "$STATE" 2>/dev/null; }

# Did something wake the chat? Read mode: a wake-up from outside newer than the
# ones already counted, and not Cache Saver's own. Fallback mode: the file
# changed well after $1 (a start or a stop).
user_back() {
  if [ "$mode" = p ]; then [ "$human" -gt "$SEEN" ] && [ "$human" -gt $(( OWN + OWNWIN )) ]
  else [ "$human" -gt $(( $1 + GRACE )) ]; fi
}
fresh() {  # something woke the chat: start the count again
  COUNT=0; STOPPED=0
  if [ "$mode" = p ]; then SEEN=$human; else SEEN=$(date +%s); fi
  save
}
# The usage limit: Claude Code records a refused request with the time the
# limit resets. Until then no nudge can run, so Cache Saver stops instead of
# counting wake-ups the user never gets.
limited() { [ "$mode" = p ] && [ "$lim" -gt 0 ] && { [ "$lim" -eq 1 ] || [ "$(date +%s)" -lt "$lim" ]; }; }
limit_note() {
  local at=""
  if [ "$lim" -gt 1 ]; then at=$(date -d "@$lim" '+%a %H:%M' 2>/dev/null || date -r "$lim" '+%a %H:%M' 2>/dev/null); fi
  if [ -n "$at" ]; then at="it resets $at"; else at="the reset time was not given"; fi
  echo "CACHE SAVER: the usage limit is reached ($at). Nothing can keep this chat warm until then, so Cache Saver stopped instead of spending wake-ups. Do NOT start it again now. When the chat is used again after the reset, start Cache Saver again and tell the user in one line: Cache Saver paused while the usage limit was reached."
}

START=$(date +%s)
read -r req human lim mode <<EOF
$(times "$FILE")
EOF
if [ -z "$req" ]; then echo "cache-saver: cannot read the chat's times"; exit 2; fi
if limited; then limit_note; exit 5; fi
# No record yet of which wake-ups were counted (first run, or an older counter
# file): the ones already there are old news, not a new wake-up.
[ "$mode" = p ] && [ "$SEEN" -eq 0 ] && SEEN=$human
if [ "$STOPPED" -gt 0 ]; then
  if user_back "$STOPPED"; then fresh
  else
    echo "CACHE SAVER: still switched off (it already spent about one cold restart's worth). Do NOT start it again until something new wakes this chat (the user, another chat, or a finished job)."
    exit 3
  fi
elif [ "$mode" = p ] && user_back; then fresh
fi

# One copy per chat. Each start writes its own token; an older copy that sees
# a different token stops (exit 4), so starting it twice never doubles the cost.
LIVE="$STATE.live"
TOKEN="$$.$START.$RANDOM"
printf '%s\n' "$TOKEN" > "$LIVE" 2>/dev/null
mine() { [ "$(cat "$LIVE" 2>/dev/null)" = "$TOKEN" ]; }
let_go() { mine && rm -f "$LIVE" 2>/dev/null; }

if [ "$MAX_NUDGES" -gt 0 ]; then
  echo "cache-saver: watching $(basename "$FILE"); nudge after $MINUTES quiet minutes; switches off at wake-up $MAX_NUDGES in a row (${COUNT} so far)"
else
  echo "cache-saver: watching $(basename "$FILE"); nudge after $MINUTES quiet minutes; never switches off"
fi

while true; do
  if ! mine; then
    echo "CACHE SAVER: a newer copy is now watching this chat, so this one stopped. Do nothing and do NOT start it again."
    exit 4
  fi
  read -r req human lim mode <<EOF
$(times "$FILE")
EOF
  if [ -z "$req" ]; then echo "cache-saver: cannot read the chat's times -- stopping"; exit 2; fi
  if limited; then limit_note; let_go; exit 5; fi
  if user_back "$START"; then fresh; fi  # something woke the chat: the count starts again
  now=$(date +%s)
  [ "$req" -gt "$now" ] && req=$now     # a clock that jumped back
  last=$req                             # the cache's hour runs from the request's START
  age=$(( now - last ))
  if [ "$age" -ge "$LIMIT" ]; then
    if [ "$MAX_NUDGES" -gt 0 ] && [ $(( COUNT + 1 )) -ge "$MAX_NUDGES" ]; then
      COUNT=$(( COUNT + 1 ))            # this last wake-up is the stop note itself
      STOPPED=$now; OWN=$now; [ "$SEEN" -lt "$now" ] && SEEN=$now; save
      away=$(( (COUNT - 1) * LIMIT + now - last ))   # the quiet stretch spanned every wake-up
      hrs=$(( (away + 1800) / 3600 )); [ "$hrs" -lt 1 ] && hrs=1
      echo "CACHE SAVER: switched off at wake-up $COUNT of $MAX_NUDGES (about $hrs hour(s) with nothing waking the chat). Keeping it on any longer would cost more usage than one fresh restart, so it stopped to save the user's usage. Do NOT start it again. Write the user a short note they will see when they come back: Cache Saver switched itself off after about $hrs quiet hour(s) because leaving it on would have cost more than it saves; the next message will re-read the chat once, and Cache Saver turns itself back on then. The next time anything wakes this chat (the user, another chat, or a finished job), start Cache Saver again and mention it in one line."
      let_go; exit 3
    fi
    COUNT=$(( COUNT + 1 )); OWN=$now; save
    if [ "$MAX_NUDGES" -gt 0 ]; then n="wake-up $COUNT of $MAX_NUDGES"; else n="nudge $COUNT"; fi
    echo "CACHE SAVER: ${age}s quiet ($n) -- reply with exactly this one line so the user knows why you woke: \"Cache Saver: kept your chat warm ($n).\" Then start Cache Saver again."
    let_go; exit 0
  fi
  # Short steps, re-reading the clock each time: a long sleep pauses while the
  # computer sleeps, and would wake up after the cache hour had run out.
  w=$(( LIMIT - age + 1 )); [ "$w" -gt 60 ] && w=60
  sleep "$w"
done
