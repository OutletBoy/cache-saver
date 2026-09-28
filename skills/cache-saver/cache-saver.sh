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
#   --max-nudges N  nudges in a row before it switches itself off (default 17,
#                   about the cost of one cold restart; 0 = never)
#   --find-me WORD  watch the chat whose transcript contains WORD: Claude puts a fresh
#                   random word in its own command, so it always finds ITS chat, even
#                   with several chats running (recommended)
#   --file PATH     transcript to watch (default: the newest one Claude Code wrote)
#
# Exit codes: 0 = nudge (reply and start again), 3 = switched off, 2 = error.

MINUTES=55
MAX_NUDGES=17
FILE=""
FIND=""
while [ $# -gt 0 ]; do
  case "$1" in
    --minutes) MINUTES="$2"; shift 2 ;;
    --max-nudges) MAX_NUDGES="$2"; shift 2 ;;
    --file) FILE="$2"; shift 2 ;;
    --find-me) FIND="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
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
#   human time    -- the newest message the USER sent. Only this means "the user
#                    is back"; Claude's own replies and background-task wake-ups
#                    never do. Claude Code marks each message with where it came
#                    from; older versions without that mark fall back to the kind
#                    of entry (a tool result or a wake-up is never the user).
# Side-chats (subagents) and error replies are skipped. Uses node, jq or python,
# whichever is present; with none, the file's modified time stands in for both.
NODE_JS='let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{let u=0,r=0,h=0,a=0;
for(const l of d.split("\n")){let o;try{o=JSON.parse(l)}catch(e){continue}
if(!o||typeof o!=="object"||o.isSidechain||typeof o.timestamp!=="string")continue;
const t=Math.floor(Date.parse(o.timestamp)/1000);if(!(t>0))continue;const m=(o.message&&typeof o.message==="object")?o.message:{};
if(o.type==="user"){u=t;a=t;if(human(o,m))h=t}else if(o.type==="assistant"&&m.usage&&m.model!=="<synthetic>"){if(u)r=u;a=t}}
if(a)console.log((r||u||a)+" "+h)});
function human(o,m){if(o.origin&&typeof o.origin==="object")return o.origin.kind==="human";
if(o.isMeta||o.isCompactSummary)return false;const c=m.content;
if(Array.isArray(c))return !c.some(x=>x&&x.type==="tool_result");
return typeof c==="string"&&!c.startsWith("<task-notification>")}'
JQ_PROG='def human: if (.origin | type) == "object" then .origin.kind == "human"
    elif .isMeta == true or .isCompactSummary == true then false
    elif (.message | type) != "object" then false
    elif (.message.content | type) == "array" then ([.message.content[] | select(type == "object" and .type == "tool_result")] | length) == 0
    elif (.message.content | type) == "string" then (.message.content | startswith("<task-notification>") | not)
    else false end;
  reduce (inputs | fromjson? | select(type == "object" and (.isSidechain | not) and (.timestamp | type) == "string")) as $o
  ({u: 0, r: 0, h: 0, a: 0};
   (($o.timestamp | sub("\\.[0-9]+"; "") | fromdateiso8601?) // 0) as $t
   | if $t == 0 then .
     elif $o.type == "user" then .u = $t | .a = $t | (if ($o | human) then .h = $t else . end)
     elif $o.type == "assistant" and ($o.message | type) == "object" and $o.message.usage != null and $o.message.model != "<synthetic>"
       then (if .u > 0 then .r = .u else . end) | .a = $t
     else . end)
  | if .a > 0 then "\(if .r > 0 then .r elif .u > 0 then .u else .a end) \(.h)" else empty end'
PY_PROG='import sys, json, datetime
def human(o, m):
    if isinstance(o.get("origin"), dict):
        return o["origin"].get("kind") == "human"
    if o.get("isMeta") or o.get("isCompactSummary"):
        return False
    c = m.get("content")
    if isinstance(c, list):
        return not any(isinstance(x, dict) and x.get("type") == "tool_result" for x in c)
    return isinstance(c, str) and not c.startswith("<task-notification>")
u = r = h = a = 0
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
    if o.get("type") == "user":
        u = a = t
        if human(o, m):
            h = t
    elif o.get("type") == "assistant" and m.get("usage") and m.get("model") != "<synthetic>":
        r = u or r
        a = t
if a:
    print(r or u or a, h)'
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
# Prints "<request start> <human time> p" when the record was read, or
# "<modified time> <modified time> f" when it could not be (the fallback).
times() {
  local out=""
  case "$PARSER" in
    node) out=$(tail -n 2000 "$1" 2>/dev/null | node -e "$NODE_JS" 2>/dev/null) ;;
    jq) out=$(tail -n 2000 "$1" 2>/dev/null | jq -Rrn "$JQ_PROG" 2>/dev/null) ;;
    ?*) out=$(tail -n 2000 "$1" 2>/dev/null | "$PARSER" -c "$PY_PROG" 2>/dev/null) ;;
  esac
  set -- $out
  if isnum "$1" && isnum "$2"; then echo "$1 $2 p"; else m=$(mtime "$FILE"); [ -n "$m" ] && echo "$(( m - EARLY )) $m f"; fi
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
# Fallback only (the record could not be read): changes to the chat this long
# after a start are Claude's own restart; later changes mean the user is back.
GRACE=120
if [ "$LIMIT" -lt 240 ]; then GRACE=$(( LIMIT / 2 )); fi
# Fallback only: the modified time is when the reply ENDED, a little after its
# request started, so the fallback counts from a bit earlier (about 3 minutes at
# the default). Early costs one slightly early nudge; late costs a full restart.
EARLY=$(( LIMIT / 20 ))

# One tiny counter file per chat:
#   "<wake-ups in a row> <switched-off time or 0> <user's messages counted up to this time>"
STATE_DIR="${CACHE_SAVER_STATE_DIR:-$CONF/cache-saver}"
mkdir -p "$STATE_DIR" 2>/dev/null
STATE="$STATE_DIR/$(basename "$FILE").state"
COUNT=0; STOPPED=0; SEEN=0
if [ -f "$STATE" ]; then read -r COUNT STOPPED SEEN < "$STATE"; fi
isnum "$COUNT" || COUNT=0
isnum "$STOPPED" || STOPPED=0
isnum "$SEEN" || SEEN=0
[ "$STOPPED" -gt "$SEEN" ] && SEEN=$STOPPED   # a counter file from an older version
save() { printf '%s %s %s\n' "$COUNT" "$STOPPED" "$SEEN" > "$STATE" 2>/dev/null; }

# Is the user back? Read mode: a user message newer than the ones already
# counted. Fallback mode: the file changed well after $1 (a start or a stop).
user_back() {
  if [ "$mode" = p ]; then [ "$human" -gt "$SEEN" ]
  else [ "$human" -gt $(( $1 + GRACE )) ]; fi
}
fresh() {  # the user is back: start the count again
  COUNT=0; STOPPED=0
  if [ "$mode" = p ]; then SEEN=$human; else SEEN=$(date +%s); fi
  save
}

START=$(date +%s)
read -r req human mode <<EOF
$(times "$FILE")
EOF
if [ -z "$req" ]; then echo "cache-saver: cannot read the chat's times"; exit 2; fi
# No record yet of which messages were counted (first run, or an older counter
# file): the messages already there are old news, not the user coming back.
[ "$mode" = p ] && [ "$SEEN" -eq 0 ] && SEEN=$human
if [ "$STOPPED" -gt 0 ]; then
  if user_back "$STOPPED"; then fresh
  else
    echo "CACHE SAVER: still switched off (it already spent about one cold restart's worth). Do NOT start it again until the user is back and asks."
    exit 3
  fi
elif [ "$mode" = p ] && user_back; then fresh
fi

if [ "$MAX_NUDGES" -gt 0 ]; then
  echo "cache-saver: watching $(basename "$FILE"); nudge after $MINUTES quiet minutes; switches off at wake-up $MAX_NUDGES in a row (${COUNT} so far)"
else
  echo "cache-saver: watching $(basename "$FILE"); nudge after $MINUTES quiet minutes; never switches off"
fi

while true; do
  read -r req human mode <<EOF
$(times "$FILE")
EOF
  if [ -z "$req" ]; then echo "cache-saver: cannot read the chat's times -- stopping"; exit 2; fi
  if user_back "$START"; then fresh; fi  # the user is back: the count starts again
  now=$(date +%s)
  [ "$req" -gt "$now" ] && req=$now     # a clock that jumped back
  last=$req                             # the cache's hour runs from the request's START
  age=$(( now - last ))
  if [ "$age" -ge "$LIMIT" ]; then
    if [ "$MAX_NUDGES" -gt 0 ] && [ $(( COUNT + 1 )) -ge "$MAX_NUDGES" ]; then
      COUNT=$(( COUNT + 1 ))            # this last wake-up is the stop note itself
      STOPPED=$now; [ "$SEEN" -lt "$now" ] && SEEN=$now; save
      if [ "$mode" = p ] && [ "$human" -gt 0 ]; then away=$(( now - human )); else away=$(( (COUNT - 1) * LIMIT + now - last )); fi
      hrs=$(( (away + 1800) / 3600 )); [ "$hrs" -lt 1 ] && hrs=1
      echo "CACHE SAVER: switched off at wake-up $COUNT of $MAX_NUDGES (about $hrs hour(s) with no messages from the user). Keeping it on any longer would cost more usage than one fresh restart, so it stopped to save the user's usage. Do NOT start it again. Write the user a short note they will see when they come back: Cache Saver switched itself off after about $hrs quiet hour(s) because leaving it on would have cost more than it saves; their next message will re-read the chat once, and Cache Saver turns itself back on then. When the user sends that next message, start Cache Saver again and mention it in one line."
      exit 3
    fi
    COUNT=$(( COUNT + 1 )); save
    if [ "$MAX_NUDGES" -gt 0 ]; then n="wake-up $COUNT of $MAX_NUDGES"; else n="nudge $COUNT"; fi
    echo "CACHE SAVER: ${age}s quiet ($n) -- reply with exactly this one line so the user knows why you woke: \"Cache Saver: kept your chat warm ($n).\" Then start Cache Saver again."
    exit 0
  fi
  sleep $(( LIMIT - age + 1 ))
done
