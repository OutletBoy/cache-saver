# Cache Saver (Cash Saver) for Claude Code -- PowerShell version.
# Same behavior as cache-saver.sh: wakes Claude before its prompt cache goes
# cold, and switches itself off once the nudges have cost about as much as one
# cold restart would. Its LAST LINE tells Claude what to do next.
#
# Usage: powershell -ExecutionPolicy Bypass -File cache-saver.ps1 [-Minutes N] [-MaxNudges N] [-FindMe WORD | -File PATH] [-Help]
#   -Minutes N: quiet minutes before a nudge (default 55; keep it a few below the
#   cache lifetime).
#   -File PATH: which chat record to watch (default: the most recently changed).
#   -MaxNudges N: wake-ups in a row before it switches itself off (default 9: each
#   nudge is two short requests, so 8 nudges plus the note cost about one cold
#   restart; 0 = never).
#   -FindMe WORD: watch the chat whose transcript contains WORD (a fresh random word
#   Claude puts in its own command), so it finds ITS chat even with several running.
# Exit codes: 0 = nudge (reply and start again), 3 = switched off, 2 = error,
#             4 = a newer copy took over this chat (do nothing),
#             5 = the usage limit is reached (start it again after the reset).
param(
  [string]$Minutes = "55",
  [string]$MaxNudges = "9",
  [string]$File = "",
  [string]$FindMe = "",
  [switch]$Help
)
if ($Help) { Get-Content -LiteralPath $PSCommandPath -TotalCount 17 | Select-Object -Skip 1 | ForEach-Object { $_ -replace '^# ?', '' }; exit 0 }

if ($Minutes -notmatch '^\d+$' -or [int]$Minutes -lt 1) { Write-Output "cache-saver: -Minutes must be a whole number, 1 or more"; exit 2 }
if ($MaxNudges -notmatch '^\d+$') { Write-Output "cache-saver: -MaxNudges must be a whole number (0 = never switch off)"; exit 2 }
$Minutes = [int]$Minutes; $MaxNudges = [int]$MaxNudges

$conf = $env:CLAUDE_CONFIG_DIR
if (-not $conf) { $conf = Join-Path $HOME ".claude" }

if ($FindMe -ne "" -and $File -eq "") {
  if ($FindMe.Length -lt 6) { Write-Output "cache-saver: -FindMe needs a unique word of 6 or more characters"; exit 2 }
  $cutoff = (Get-Date).AddMinutes(-10)
  $hits = @(Get-ChildItem -Path (Join-Path $conf "projects") -Filter *.jsonl -Recurse -Depth 1 -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $cutoff } |
    Where-Object { Select-String -LiteralPath $_.FullName -SimpleMatch -Pattern $FindMe -Quiet })
  if ($hits.Count -eq 1) { $File = $hits[0].FullName }
  elseif ($hits.Count -eq 0) { Write-Output "cache-saver: no chat contains '$FindMe' yet -- start it again with a new random word"; exit 2 }
  else { Write-Output "cache-saver: $($hits.Count) chats contain '$FindMe' -- start it again with a new random word"; exit 2 }
}
if ($File -eq "") {
  $root = Join-Path $conf "projects"
  $newest = Get-ChildItem -Path $root -Filter *.jsonl -Recurse -Depth 1 -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($null -eq $newest) { Write-Output "cache-saver: no chat transcript found under $root -- pass one with -File"; exit 2 }
  $File = $newest.FullName
}
if (-not (Test-Path -LiteralPath $File)) { Write-Output "cache-saver: file not found: $File"; exit 2 }

function Get-Epoch([datetime]$t) { [int64]([datetimeoffset]$t).ToUnixTimeSeconds() }
function Get-MTime { Get-Epoch (Get-Item -LiteralPath $File).LastWriteTime }

# Reading the chat's record (same rules as cache-saver.sh). Every entry carries
# its kind and its time; nothing else is used. Two times matter:
#   request start -- the cache's hour restarts when a request to Claude STARTS,
#                    not when its reply ends: right after the newest entry before
#                    the newest reply (a message, a tool result, or a wake-up).
#   wake time     -- the newest entry that woke the chat: the user's message, or
#                    anything that arrived while Claude was idle (its last reply had
#                    ended its turn) -- another chat's message, a finished job, a
#                    scheduled wake-up. The cache got used, so the count starts
#                    again (a loop saves with nobody at the keyboard). Entries in the
#                    middle of Claude's own work never count; Cache Saver's own
#                    wake-up is told apart by its time.
# Side-chats (subagents) and error replies are skipped; a usage-limit error (Claude
# Code writes the reset time beside it) is remembered until the next real reply.
# Returns @(request start, wake time, "p", limit reset or 0 -- 1 when unknown),
# or @(modified time, modified time, "f", 0) when the record cannot be read.
function Test-Woke($o, [bool]$idle) {
  if ($o.isCompactSummary -eq $true) { return $false }
  if ($null -eq $o.message) { return $false }
  $c = $o.message.content
  if ($c -is [array]) { foreach ($x in $c) { if ($null -ne $x -and $x.type -eq "tool_result") { return $false } } }
  elseif (-not ($c -is [string])) { return $false }
  if ($null -ne $o.origin -and $o.origin.kind -eq "human") { return $true }
  return $idle
}
function Get-Times {
  $u = [int64]0; $r = [int64]0; $h = [int64]0; $a = [int64]0; $idle = $true; $lim = [int64]0
  # Test hook: CACHE_SAVER_PARSER=none forces the fallback.
  if ($env:CACHE_SAVER_PARSER -ne "none") { try {
    $lines = Get-Content -LiteralPath $File -Tail 2000 -Encoding UTF8 -ErrorAction Stop
    foreach ($l in $lines) {
      if ($l -notmatch '"type":"(user|assistant)"') { continue }
      try { $o = $l | ConvertFrom-Json -ErrorAction Stop } catch { continue }
      if ($null -eq $o -or $o.isSidechain -eq $true -or $null -eq $o.timestamp) { continue }
      try {
        if ($o.timestamp -is [datetime]) { $t = Get-Epoch $o.timestamp }
        else { $t = [datetimeoffset]::Parse([string]$o.timestamp, [cultureinfo]::InvariantCulture).ToUnixTimeSeconds() }
      } catch { continue }
      if ($o.type -eq "assistant" -and $o.isApiErrorMessage -eq $true -and $o.error -eq "rate_limit") {
        $z = $null; if ($null -ne $o.quotaLimits) { $z = $o.quotaLimits.resetsAt }
        if (($z -is [int] -or $z -is [long]) -and $z -gt 0) { $lim = [int64]$z } else { $lim = 1 }
        continue
      }
      if ($o.type -eq "user") { $u = $t; $a = $t; if (Test-Woke $o $idle) { $h = $t } }
      elseif ($o.type -eq "assistant" -and $null -ne $o.message -and $null -ne $o.message.usage -and $o.message.model -ne "<synthetic>") {
        if ($u -gt 0) { $r = $u }
        $a = $t; $lim = 0
        $sr = $o.message.stop_reason
        if ($sr) { $idle = ($sr -ne "tool_use" -and $sr -ne "pause_turn") }
      }
    }
  } catch { } }
  if ($a -gt 0) {
    if ($r -eq 0) { if ($u -gt 0) { $r = $u } else { $r = $a } }
    return @($r, $h, "p", $lim)
  }
  $m = Get-MTime
  if ($null -eq $m) { return $null }
  return @(($m - $script:early), $m, "f", 0)
}

$limit = $Minutes * 60
if ($env:CACHE_SAVER_TEST_SECONDS -match '^\d+$') { $limit = [int]$env:CACHE_SAVER_TEST_SECONDS }
# Fallback only: file changes this soon after a start or a stop are Claude's
# own restart, not someone waking the chat.
$grace = 120
if ($limit -lt 240) { $grace = [int][math]::Floor($limit / 2) }
# A wake-up this soon after Cache Saver's own exit is its own (the task
# notification lands within seconds), not someone else waking the chat.
$ownwin = 60
if ($limit -lt 120) { $ownwin = [int][math]::Floor($limit / 2) }
# Fallback only: the modified time is when the reply ENDED, a little after its
# request started, so the fallback counts from a bit earlier (about 3 minutes at
# the default). Early costs one slightly early nudge; late costs a full restart.
$early = [int][math]::Floor($limit / 20)

# One tiny counter file per chat:
#   "<wake-ups in a row> <switched-off time or 0> <wake-ups from outside counted
#    up to this time> <Cache Saver's own last exit>"
$stateDir = $env:CACHE_SAVER_STATE_DIR
if (-not $stateDir) { $stateDir = Join-Path $conf "cache-saver" }
New-Item -ItemType Directory -Force -Path $stateDir -ErrorAction SilentlyContinue | Out-Null
$state = Join-Path $stateDir ((Split-Path $File -Leaf) + ".state")
$count = 0; $stopped = [int64]0; $seen = [int64]0; $own = [int64]0
if (Test-Path -LiteralPath $state) {
  $parts = @((Get-Content -LiteralPath $state -TotalCount 1) -split '\s+')
  if ($parts.Count -ge 2 -and $parts[0] -match '^\d+$' -and $parts[1] -match '^\d+$') {
    $count = [int]$parts[0]; $stopped = [int64]$parts[1]
    if ($parts.Count -ge 3 -and $parts[2] -match '^\d+$') { $seen = [int64]$parts[2] }
    if ($parts.Count -ge 4 -and $parts[3] -match '^\d+$') { $own = [int64]$parts[3] }
  }
}
if ($stopped -gt $seen) { $seen = $stopped }       # a counter file from an older version
function Save-State { Set-Content -LiteralPath $state -Value "$count $stopped $seen $own" -Encoding ascii -ErrorAction SilentlyContinue }

# Did something wake the chat? Read mode: a wake-up from outside newer than the
# ones already counted, and not Cache Saver's own. Fallback mode: the file
# changed well after $since (a start or a stop).
function Test-UserBack($times, [int64]$since) {
  if ($times[2] -eq "p") { return ($times[1] -gt $script:seen -and $times[1] -gt ($script:own + $ownwin)) }
  return ($times[1] -gt ($since + $grace))
}
function Reset-Fresh($times) {
  $script:count = 0; $script:stopped = 0
  if ($times[2] -eq "p") { $script:seen = $times[1] } else { $script:seen = Get-Epoch (Get-Date) }
  Save-State
}
# The usage limit (same rule as cache-saver.sh): a refused request is recorded
# with the time the limit resets; until then no nudge can run.
function Test-Limited($times) {
  if ($times[2] -ne "p" -or [int64]$times[3] -le 0) { return $false }
  if ([int64]$times[3] -eq 1) { return $true }
  return ((Get-Epoch (Get-Date)) -lt [int64]$times[3])
}
function Write-LimitNote($times) {
  $at = "the reset time was not given"
  if ([int64]$times[3] -gt 1) { $at = "it resets " + [datetimeoffset]::FromUnixTimeSeconds([int64]$times[3]).LocalDateTime.ToString("ddd HH:mm", [cultureinfo]::InvariantCulture) }
  Write-Output ("CACHE SAVER: the usage limit is reached ($at). Nothing can keep this chat warm until then, so Cache Saver stopped instead of spending wake-ups. Do NOT start it again now. When the chat is used again after the reset, start Cache Saver again and tell the user in one line: Cache Saver paused while the usage limit was reached.")
}

$start = Get-Epoch (Get-Date)
$times = Get-Times
if ($null -eq $times) { Write-Output "cache-saver: cannot read the chat's times"; exit 2 }
if (Test-Limited $times) { Write-LimitNote $times; exit 5 }
# No record yet of which wake-ups were counted (first run, or an older counter
# file): the ones already there are old news, not a new wake-up.
if ($times[2] -eq "p" -and $seen -eq 0) { $seen = [int64]$times[1] }
if ($stopped -gt 0) {
  if (Test-UserBack $times $stopped) { Reset-Fresh $times }
  else {
    Write-Output "CACHE SAVER: still switched off (it already spent about one cold restart's worth). Do NOT start it again until something new wakes this chat (the user, another chat, or a finished job)."
    exit 3
  }
} elseif ($times[2] -eq "p" -and (Test-UserBack $times $start)) { Reset-Fresh $times }

# One copy per chat. Each start writes its own token; an older copy that sees
# a different token stops (exit 4), so starting it twice never doubles the cost.
$live = "$state.live"
$token = "$PID.$start." + (Get-Random)
Set-Content -LiteralPath $live -Value $token -Encoding ascii -ErrorAction SilentlyContinue
function Test-Mine { $v = Get-Content -LiteralPath $script:live -TotalCount 1 -ErrorAction SilentlyContinue; return ($v -eq $script:token) }
function Clear-Live { if (Test-Mine) { Remove-Item -LiteralPath $script:live -Force -ErrorAction SilentlyContinue } }

$leaf = Split-Path $File -Leaf
if ($MaxNudges -gt 0) {
  Write-Output "cache-saver: watching $leaf; nudge after $Minutes quiet minutes; switches off at wake-up $MaxNudges in a row ($count so far)"
} else {
  Write-Output "cache-saver: watching $leaf; nudge after $Minutes quiet minutes; never switches off"
}

while ($true) {
  if (-not (Test-Mine)) {
    Write-Output "CACHE SAVER: a newer copy is now watching this chat, so this one stopped. Do nothing and do NOT start it again."
    exit 4
  }
  $times = Get-Times
  if ($null -eq $times) { Write-Output "cache-saver: cannot read the chat's times -- stopping"; exit 2 }
  if (Test-Limited $times) { Write-LimitNote $times; Clear-Live; exit 5 }
  if (Test-UserBack $times $start) { Reset-Fresh $times }   # something woke the chat: the count starts again
  $now = Get-Epoch (Get-Date)
  $last = [math]::Min([int64]$times[0], $now)       # the cache's hour runs from the request's START
  $age = $now - $last
  if ($age -ge $limit) {
    if ($MaxNudges -gt 0 -and ($count + 1) -ge $MaxNudges) {
      $count++                                   # this last wake-up is the stop note itself
      $stopped = $now; $own = $now; if ($seen -lt $now) { $seen = $now }; Save-State
      $away = ($count - 1) * $limit + $age        # the quiet stretch spanned every wake-up
      $hrs = [int][math]::Floor(($away + 1800) / 3600); if ($hrs -lt 1) { $hrs = 1 }
      Write-Output ("CACHE SAVER: switched off at wake-up $count of $MaxNudges (about $hrs hour(s) with nothing waking the chat). Keeping it on any longer would cost more usage than one fresh restart, so it stopped to save the user's usage. Do NOT start it again. Write the user a short note they will see when they come back: Cache Saver switched itself off after about $hrs quiet hour(s) because leaving it on would have cost more than it saves; the next message will re-read the chat once, and Cache Saver turns itself back on then. The next time anything wakes this chat (the user, another chat, or a finished job), start Cache Saver again and mention it in one line.")
      Clear-Live; exit 3
    }
    $count++; $own = $now; Save-State
    if ($MaxNudges -gt 0) { $n = "wake-up $count of $MaxNudges" } else { $n = "nudge $count" }
    Write-Output "CACHE SAVER: ${age}s quiet ($n) -- reply with exactly this one line so the user knows why you woke: `"Cache Saver: kept your chat warm ($n).`" Then start Cache Saver again."
    Clear-Live; exit 0
  }
  # Short steps, re-reading the clock each time: a long sleep pauses while the
  # computer sleeps, and would wake up after the cache hour had run out.
  $w = $limit - $age + 1; if ($w -gt 60) { $w = 60 }
  Start-Sleep -Seconds $w
}
