#!/usr/bin/env bash
# Cache Saver behavior tests: request-start timing and "is the user back".
# Needs GNU date (Linux, Git Bash). Usage: bash tests/run-tests.sh sh|ps1 [reader]   reader: node|jq|py|none (sh), json|none (ps1)
KIND="$1"; READER="${2:-}"
D="$(cd "$(dirname "$0")/../skills/cache-saver" && pwd)"
W=$(mktemp -d)
export CACHE_SAVER_TEST_SECONDS=60 CACHE_SAVER_STATE_DIR="$W/state"
case "$READER" in
  ''|json) unset CACHE_SAVER_PARSER ;;
  py) pp=""; for p in python3 python py; do c=$(command -v "$p" 2>/dev/null) || continue   # a real Python, as the script picks it
        case "$c" in *WindowsApps*) continue ;; esac; pp="$c"; break; done
      export CACHE_SAVER_PARSER="$pp" ;;
  *) export CACHE_SAVER_PARSER="$READER" ;;
esac
mkdir -p "$W/state"
iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.123Z; }
# U = tool result, H = the user's message (marked human), T = background-task wake-up (marked),
# X = another chat's message (a loop), O = the user's message from an older Claude Code (no mark),
# N = an older wake-up (no mark),
# A = Claude's reply, M = a metadata line.
U() { printf '{"parentUuid":null,"isSidechain":%s,"promptId":"p","type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"x \\"type\\":\\"assistant\\""}]},"uuid":"u","timestamp":"%s"}\n' "${2:-false}" "$(iso "$1")"; }
H() { printf '{"parentUuid":null,"isSidechain":false,"promptId":"p","type":"user","message":{"role":"user","content":"hello"},"uuid":"h","timestamp":"%s","origin":{"kind":"human"}}\n' "$(iso "$1")"; }
T() { printf '{"parentUuid":null,"isSidechain":false,"promptId":"p","type":"user","message":{"role":"user","content":"<task-notification>done</task-notification>"},"uuid":"t","timestamp":"%s","origin":{"kind":"task-notification"}}\n' "$(iso "$1")"; }
O() { printf '{"parentUuid":null,"isSidechain":false,"type":"user","message":{"role":"user","content":[{"type":"text","text":"hello"}]},"uuid":"o","timestamp":"%s"}\n' "$(iso "$1")"; }
N() { printf '{"parentUuid":null,"isSidechain":false,"type":"user","message":{"role":"user","content":"<task-notification>done</task-notification>"},"uuid":"n","timestamp":"%s"}\n' "$(iso "$1")"; }
A() { printf '{"parentUuid":"u","isSidechain":%s,"message":{"model":"%s","id":"m","type":"message","role":"assistant","content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":1},"stop_reason":"%s"},"requestId":"r","type":"assistant","uuid":"a","timestamp":"%s"}\n' "${2:-false}" "${3:-claude-x}" "${4:-end_turn}" "$(iso "$1")"; }
X() { printf '{"parentUuid":null,"isSidechain":false,"type":"user","message":{"role":"user","content":"<cross-session-message>next job</cross-session-message>"},"uuid":"x","timestamp":"%s","origin":{"kind":"peer"}}\n' "$(iso "$1")"; }
# Lm = Claude Code's usage-limit error entry: Lm <time> <reset time or none> [error kind]
Lm() { local q=""; [ "${2:-none}" != none ] && q="\"quotaLimits\":{\"status\":\"rejected\",\"resetsAt\":$2,\"rateLimitType\":\"seven_day\"},"; printf '{"parentUuid":"u","isSidechain":false,"type":"assistant","uuid":"l","timestamp":"%s","message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"You have hit your weekly limit"}],"usage":{"input_tokens":0},"stop_reason":"stop_sequence"},%s"error":"%s","isApiErrorMessage":true}\n' "$(iso "$1")" "$q" "${3:-rate_limit}"; }
M() { printf '{"type":"frame-link","sessionId":"s","timestamp":"%s"}\n' "$(iso "$1")"; }
run() {  # run <file> <timeout-seconds>; prints "<exit> <elapsed> <last line>"
  local t0=$(date +%s) out rc
  if [ "$KIND" = sh ]; then out=$(timeout "$2" bash "$D/cache-saver.sh" --file "$1" < /dev/null); rc=$?
  else out=$(timeout "$2" powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$D/cache-saver.ps1")" -File "$(cygpath -w "$1")" < /dev/null); rc=$?; out=$(printf '%s' "$out" | tr -d '\r'); fi
  echo "$rc $(( $(date +%s) - t0 )) $(printf '%s\n' "$out" | tail -1 | cut -c1-160)"
}
runfm() {  # runfm <config-dir> <word> <timeout>
  local t0=$(date +%s) out rc
  if [ "$KIND" = sh ]; then out=$(CLAUDE_CONFIG_DIR="$1" timeout "$3" bash "$D/cache-saver.sh" --find-me "$2" < /dev/null); rc=$?
  else out=$(CLAUDE_CONFIG_DIR="$(cygpath -w "$1")" timeout "$3" powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$D/cache-saver.ps1")" -FindMe "$2" < /dev/null); rc=$?; out=$(printf '%s' "$out" | tr -d '\r'); fi
  echo "$rc $(( $(date +%s) - t0 )) $(printf '%s\n' "$out" | tail -1 | cut -c1-160)"
}
pass=0; fail=0
check() {  # check <name> <result> <want-exit> <max-elapsed> [<min-elapsed>] [<grep>]
  set -- "$1" "$2" "$3" "$4" "${5:-0}" "${6:-}"
  local rc=${2%% *} rest=${2#* }; local el=${rest%% *}
  if [ "$rc" = "$3" ] && [ "$el" -le "$4" ] && [ "$el" -ge "$5" ] && { [ -z "$6" ] || printf '%s' "$2" | grep -q -- "$6"; }; then
    pass=$((pass+1)); echo "PASS $1: $2"; else fail=$((fail+1)); echo "FAIL $1: $2 (want exit $3, elapsed $5..$4 ${6:+, '$6'})"; fi
}
st() { printf '%s\n' "$2" > "$W/state/$1.state"; }
FALLBACK=no; [ "$READER" = none ] && FALLBACK=yes

if [ $FALLBACK = no ]; then
n=$(date +%s)
# A: request started 70 s ago, reply landed 5 s ago -> nudge NOW (timing from the end waited ~55 s)
f=$W/a.jsonl; { U $((n-70)); A $((n-5)); } > $f
check A-start-anchor "$(run $f 30)" 0 20 0 "quiet"
# B: request started 20 s ago -> waits until 60 s after the START (about 40 s)
n=$(date +%s); f=$W/b.jsonl; { U $((n-20)); A $((n-5)); } > $f
check B-waits-from-start "$(run $f 90)" 0 55 30 "quiet"
# C: a later metadata line does not push the timer back
n=$(date +%s); f=$W/c.jsonl; { U $((n-70)); A $((n-65)); M $n; } > $f
check C-metadata-ignored "$(run $f 30)" 0 20 0 "quiet"
# D: a subagent's side-chat entries do not count
n=$(date +%s); f=$W/d.jsonl; { U $((n-70)); A $((n-65)); U $((n-2)) true; A $((n-1)) true; } > $f
check D-sidechain-ignored "$(run $f 30)" 0 20 0 "quiet"
# E: an error reply (no real request) does not count
n=$(date +%s); f=$W/e.jsonl; { U $((n-70)); A $((n-65)); U $((n-4)); A $((n-3)) false "<synthetic>"; } > $f
check E-error-reply "$(run $f 30)" 0 20 0 "quiet"
# F: an interrupt note after the reply does not move the request start
n=$(date +%s); f=$W/f.jsonl; { U $((n-70)); A $((n-65)); U $((n-3)); } > $f
check F-interrupt "$(run $f 30)" 0 20 0 "quiet"
# K: Cache Saver's OWN stop-note wake-up does not turn it back on
n=$(date +%s); f=$W/k.jsonl; { H $((n-5000)); A $((n-4990)); T $((n-97)); A $((n-95)); } > $f; st k.jsonl "9 $((n-100)) $((n-100)) $((n-100))"
check K-own-wakeup-stays-off "$(run $f 30)" 3 20 0 "still switched off"
# K2: a finished background job later on DOES wake the chat: it turns back on
n=$(date +%s); f=$W/k2.jsonl; { H $((n-5000)); A $((n-4990)); T $((n-2)); A $((n-1)); } > $f; st k2.jsonl "9 $((n-100)) $((n-100)) $((n-100))"
check K2-job-wakes-it "$(run $f 8)" 124 12 5 "0 so far"
# K3: another chat's message (an autonomous loop, nobody at the keyboard) turns it back on
n=$(date +%s); f=$W/k3.jsonl; { H $((n-5000)); A $((n-4990)); X $((n-2)); A $((n-1)); } > $f; st k3.jsonl "9 $((n-100)) $((n-100)) $((n-100))"
check K3-loop-wakes-it "$(run $f 8)" 124 12 5 "0 so far"
# L: the user's own message after the switch-off turns it back on
n=$(date +%s); f=$W/l.jsonl; { H $((n-5000)); A $((n-4990)); H $((n-2)); A $((n-1)); } > $f; st l.jsonl "9 $((n-100)) $((n-100))"
check L-user-back "$(run $f 8)" 124 12 5 "0 so far"
# M: Claude's own tool results (for example a slow nudge reply) do not restart the count
n=$(date +%s); f=$W/m.jsonl; { H $((n-5000)); A $((n-4990)); U $((n-70)); A $((n-65)); } > $f; st m.jsonl "5 0 $((n-5000))"
check M-own-activity-keeps-count "$(run $f 30)" 0 20 0 "wake-up 6 of 9"
# P: a new user message restarts the count
n=$(date +%s); f=$W/p.jsonl; { H $((n-5000)); A $((n-4990)); H $((n-80)); A $((n-75)); } > $f; st p.jsonl "5 0 $((n-5000))"
check P-user-restarts-count "$(run $f 30)" 0 20 0 "wake-up 1 of 9"
# Q: an older Claude Code (no marks): a plain message counts as the user...
n=$(date +%s); f=$W/q.jsonl; { O $((n-80)); A $((n-75)); } > $f; st q.jsonl "5 0 $((n-5000))"
check Q-old-version-user "$(run $f 30)" 0 20 0 "wake-up 1 of 9"
# R: ...and so does an unmarked wake-up from a finished job
n=$(date +%s); f=$W/r.jsonl; { O $((n-5000)); A $((n-4990)); N $((n-80)); A $((n-75)); } > $f; st r.jsonl "5 0 $((n-5000))"
check R-old-version-wakeup "$(run $f 30)" 0 20 0 "wake-up 1 of 9"
# V: Cache Saver's OWN nudge wake-up keeps the count going
n=$(date +%s); f=$W/v.jsonl; { H $((n-5000)); A $((n-4990)); T $((n-80)); A $((n-75)); } > $f; st v.jsonl "5 0 $((n-5000)) $((n-82))"
check V-own-nudge-keeps-count "$(run $f 30)" 0 20 0 "wake-up 6 of 9"
# W: in a loop, another chat's message restarts the count with no human at all
n=$(date +%s); f=$W/w.jsonl; { H $((n-5000)); A $((n-4990)); X $((n-80)); A $((n-75)); } > $f; st w.jsonl "5 0 $((n-5000)) $((n-3000))"
check W-loop-restarts-count "$(run $f 30)" 0 20 0 "wake-up 1 of 9"
# S: a counter file from an older version (two numbers) stays switched off
n=$(date +%s); f=$W/s.jsonl; { H $((n-300)); A $((n-290)); } > $f; st s.jsonl "9 $((n-100))"
check S-old-counter-file "$(run $f 30)" 3 20 0 "still switched off"
# Y: a wake-up that lands while Claude is still working (not idle) does not restart the count
n=$(date +%s); f=$W/y.jsonl; { H $((n-5000)); A $((n-4990)); U $((n-90)); A $((n-85)) false claude-x tool_use; T $((n-80)); U $((n-75)); A $((n-70)); } > $f; st y.jsonl "5 0 $((n-5000)) $((n-3000))"
check Y-mid-work-wakeup-ignored "$(run $f 30)" 0 20 0 "wake-up 6 of 9"
# Z: your own message counts even while Claude is working
n=$(date +%s); f=$W/z.jsonl; { H $((n-5000)); A $((n-4990)); U $((n-90)); A $((n-85)) false claude-x tool_use; H $((n-80)); U $((n-75)); A $((n-70)); } > $f; st z.jsonl "5 0 $((n-5000)) $((n-3000))"
check Z-your-message-mid-work "$(run $f 30)" 0 20 0 "wake-up 1 of 9"
# FM: --find-me finds the one chat containing the word
C=$W/conf; mkdir -p $C/projects/p1 $C/projects/p2; n=$(date +%s)
{ H $((n-70)); A $((n-65)); echo '{"type":"note","text":"cs-q7z3m9x"}'; } > $C/projects/p1/one.jsonl; { H $((n-70)); A $((n-65)); } > $C/projects/p2/two.jsonl
check FM-find-me "$(runfm $C cs-q7z3m9x 30)" 0 20 0 "quiet"
# FM2: a word in two chats is refused, not guessed
echo '{"type":"note","text":"cs-q7z3m9x"}' >> $C/projects/p2/two.jsonl
check FM2-find-me-ambiguous "$(runfm $C cs-q7z3m9x 30)" 2 20 0 "2 chats contain"
# DUP: starting a second copy on the same chat stops the first (exit 4), so the cost never doubles
n=$(date +%s); f=$W/dup.jsonl; { H $n; A $n; } > $f; rm -f $W/state/dup.jsonl.state*
run $f 150 > $W/dup1.out & p1=$!; sleep 5
run $f 150 > $W/dup2.out & p2=$!
wait $p1; check DUP-first-copy-steps-aside "$(cat $W/dup1.out)" 4 75 50 "newer copy"
wait $p2; check DUP-second-copy-keeps-watch "$(cat $W/dup2.out)" 0 75 50 "quiet"
# LIM1: the usage limit is reached (reset time given) -> stops at once, says when it resets
n=$(date +%s); f=$W/lim1.jsonl; { H $((n-20)); Lm $((n-19)) $((n+3600)); } > $f
check LIM1-limit-stops "$(run $f 30)" 5 20 0 "usage limit is reached (it resets"
# LIM2: no reset time in the entry -> still stops, and says the time is unknown
n=$(date +%s); f=$W/lim2.jsonl; { H $((n-20)); Lm $((n-19)) none; } > $f
check LIM2-limit-no-time "$(run $f 30)" 5 20 0 "reset time was not given"
# LIM3: the reset time has passed -> works normally again
n=$(date +%s); f=$W/lim3.jsonl; { U $((n-70)); A $((n-65)); H $((n-62)); Lm $((n-61)) $((n-10)); } > $f
check LIM3-limit-over "$(run $f 30)" 0 20 0 "quiet"
# LIM4: a real reply after the limit entry means the chat works again
n=$(date +%s); f=$W/lim4.jsonl; { U $((n-70)); Lm $((n-69)) $((n+3600)); A $((n-65)); } > $f
check LIM4-reply-clears-limit "$(run $f 30)" 0 20 0 "quiet"
# LIM5: a different error (a server hiccup) is not the usage limit
n=$(date +%s); f=$W/lim5.jsonl; { U $((n-70)); A $((n-65)); H $((n-62)); Lm $((n-61)) $((n+3600)) server_error; } > $f
check LIM5-other-error "$(run $f 30)" 0 20 0 "quiet"
# LIM6: the limit is hit while it is watching -> stops at the next check instead of nudging
n=$(date +%s); f=$W/lim6.jsonl; { H $n; A $n; } > $f; rm -f $W/state/lim6.jsonl.state*
( sleep 5; Lm $(date +%s) $(( $(date +%s) + 3600 )) >> $f ) &
check LIM6-limit-while-watching "$(run $f 150)" 5 75 50 "usage limit is reached"
fi
# G: no readable entries -> falls back to the file's modified time
f=$W/g.jsonl; echo "not json" > $f; touch -d "@$(( $(date +%s) - 70 ))" $f
check G-fallback-mtime "$(run $f 30)" 0 20 0 "quiet"
# G2: the fallback leans EARLY: changed 58 s ago with a 60 s limit -> nudges now, not in 2-3 s
if [ $FALLBACK = yes ]; then
f=$W/g2.jsonl; echo "x" > $f; touch -d "@$(( $(date +%s) - 58 ))" $f
check G2-fallback-leans-early "$(run $f 30)" 0 1 0 "quiet"
fi
# H: at the last allowed wake-up it switches off
n=$(date +%s); f=$W/h.jsonl
if [ $FALLBACK = no ]; then { H $((n-70)); A $((n-65)); } > $f; else echo "x" > $f; touch -d "@$((n-70))" $f; fi
st h.jsonl "8 0"
check H-switch-off "$(run $f 30)" 3 20 0 "switched off at wake-up 9"
# I: still off when nothing new happened
check I-stays-off "$(run $f 30)" 3 20 0 "still switched off"
# J: the user came back (a new message after the switch-off) -> starts fresh and waits
n=$(date +%s); st h.jsonl "9 $((n-100)) $((n-100))"; H $n >> $f; A $((n+1)) >> $f
check J-user-back "$(run $f 8)" 124 12 5 "0 so far"
echo "$KIND ${READER:-default}: $pass passed, $fail failed"
rm -rf "$W"
[ "$fail" -eq 0 ]
