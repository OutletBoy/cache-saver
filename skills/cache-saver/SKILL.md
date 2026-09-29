---
name: cache-saver
description: Cache Saver (Cash Saver) keeps a Claude Code chat's prompt cache warm while the user steps away or while the chat waits in an autonomous loop, so their 5-hour window and weekly limit last longer, and switches itself off at the break-even point. Use when the user asks to start or stop Cache Saver, mentions keeping the cache warm, stepping away, a break, lunch, a meeting, going to bed or leaving for a while, asks how to save usage or limits, or asks any question about how Cache Saver works, what it saves, or when to use it.
---

# Cache Saver (Cash Saver) for Claude Code

You are the user's guide to Cache Saver. Start it, stop it, follow its output, and answer their
questions about it in plain, friendly words. The user may be a beginner.

## What it is, in one breath

Claude Code keeps a saved copy of the chat (the prompt cache) for about 1 hour on subscription plans.
After that, the next message re-reads the whole chat at about 2x the normal input rate, instead of
0.1x from a warm cache. Cache Saver is a tiny script that runs as a background task, waits until 55
minutes after your last request STARTED (the cache's hour restarts when a request starts, not when
the reply ends), then exits. That wakes you; you reply with one short line, which
refreshes the cache for another hour; then you start it again. Each nudge is two short requests
(your reply and the restart), so one cold restart is worth about 9 nudges.

## How to start it

Run this as a BACKGROUND task (the script sits in this skill's folder). Replace `WORD` with a
fresh random word you make up every time you start it: `cs-` followed by 8 random letters and
digits. Never reuse a word, and never copy one from anywhere, this file included:

```bash
bash ~/.claude/skills/cache-saver/cache-saver.sh --find-me WORD
```

The word is written into this chat's own record the moment you run the command, so Cache Saver finds
and watches THIS chat, even when the user runs several chats at once. If it says no chat or several
chats contain the word, start it again ONCE with a new word; if that fails too, tell the user and
use `--file` with this chat's record instead.

(If the user set `CLAUDE_CONFIG_DIR`, the folder is `$CLAUDE_CONFIG_DIR/skills/cache-saver/`. On
Windows without bash: `powershell -ExecutionPolicy Bypass -File <that folder>\cache-saver.ps1 -FindMe WORD`.)

If the user is asked to approve the command every time, suggest allowing the script itself: add
`Bash(bash ~/.claude/skills/cache-saver/cache-saver.sh:*)` to `permissions.allow` in
`~/.claude/settings.json` (the word changes each start, so a one-off approval does not stick).

Then tell the user in one line that Cache Saver is on, and that they can say "stop the cache saver".

## Every time it finishes: do what its last line says

- **Exit 0, a line starting `CACHE SAVER: ... quiet (wake-up N of 9)`**: reply with exactly the one line
  it gives, such as "Cache Saver: kept your chat warm (wake-up 3 of 9).", so the user can see why
  you woke, and start it again as a background task. Keep
  this reply short; it is what refreshes the cache.
- **Exit 3, `CACHE SAVER: switched off at wake-up ...`**: do NOT start it again. Write the user a short,
  clear note they will see when they come back, as the line asks: it switched itself off after about
  that many quiet hours because staying on would have cost more usage than one fresh restart; their
  next message re-reads the chat once; Cache Saver turns itself back on then.
- **Exit 3, `still switched off`**: do not start it again until something new wakes this chat.
- **Exit 2 (an error)**: tell the user the message in plain words and do not loop. A common one is
  "no chat transcript found": pass the chat file with `--file`. (For the find-me messages, see above.)
- **Exit 4, `a newer copy is now watching this chat`**: do nothing. Another copy took over; do not
  start it again and do not mention it.
- **Exit 5, `the usage limit is reached`**: the user's usage limit was hit, so no nudge can run until
  it resets. Do not start it again now. The next time the chat is used after the reset, start it
  again and tell the user in one line that Cache Saver paused while the limit was reached.

## When something wakes the chat after it switched itself off

It switched off only because nothing had woken the chat for about 8 hours. So the **next time
anything wakes it** (the user's message, another chat's message in a loop, or a finished background
job), start it again yourself, without asking, and add one short line to your answer, for example:
"Cache Saver switched off during the quiet stretch to save usage; it is back on now." Asking would only add a
question to every return, and a returning user is exactly who Cache Saver is for.

Do NOT turn it back on when:
- **the user stopped it themselves** ("stop the cache saver"): it stays off until they ask again;
- the user's message says they are leaving for **more than about 8 hours** (suggest leaving it off);
- the user says they are **done with this chat**.

## Things that stop it silently (help the user with these)

It dies with the chat: closing the chat, terminal, or Claude Code; a computer restart, shutdown,
crash, or Claude Code update; `/clear` or a new chat (it was watching the old one); and sometimes a
compaction. It also cannot keep the cache warm while the computer is asleep or offline, while you are
waiting for the user to approve a command (suggest "always allow" for it), or while the usage limit is
hit (it notices the limit, stops with exit 5, and says when it resets). If the user asks "is Cache Saver on?", check whether its background task is still running and
say so plainly; if it is not, offer to start it. Each wake-up adds about 1,000 tokens to the chat (about
9,000 over a full 8-hour run): if the user is stepping away with the chat almost full (less than
about 5% left before auto-compact), suggest running `/compact` first, then start Cache Saver again. Recommend the `CLAUDE.md` block below so it starts
in every new chat by itself.

## How to stop it

When the user says "stop the cache saver" (or anything like it), stop the background task and do not
start it again. Closing the chat also stops it.

## The one rule (use it for every recommendation)

- Back within **about 8 hours**: leave it on. It saves.
- Away **longer** (overnight, a weekend, a trip): turn it off before going. It also switches itself off at its 9th
  wake-up in a row (about 8 quiet hours): instead of a 9th nudge, that wake-up is your note to the
  user. The nudges then total about one cold restart, the most it can ever cost extra (the classic
  rent-or-buy strategy: keep paying the small cost until it adds up to the big one, then stop).
- **Not worth it** for short chats (re-reading is cheap anyway), or a chat the user is done with.
- If the user says they are leaving for longer than about 8 hours, suggest stopping it now.

## The numbers (for questions about savings)

Measured from thousands of real Claude Code turns: one cold restart costs about as much as 18 warm
requests, and each nudge is two requests, so about 9 nudges. Share of the break's cost saved:

| Break | Saved |
|---|---|
| 1 hour | 78% |
| 2 hours | 67% |
| 3 hours | 56% |
| 4 hours | 44% |
| 6 hours | 22% |
| 8 hours | about 0% (break-even; it switches itself off) |
| Overnight or longer | costs about one extra restart: turn it off |
| Normal work day (a 1-hour lunch and a 2-hour meeting) | about 72% |

The first message back is about 18 times cheaper. Bigger chats save more in absolute terms. Anthropic
does not publish how many tokens one percent of a subscription limit is, so savings are a share of
what the break would have cost. On the pay-per-token API with the 1-hour cache, the same percentages apply to the bill.

## Options

| Option | What it does | Default |
|---|---|---|
| `--minutes N` | Quiet minutes before a nudge (keep it a few below the cache lifetime) | 55 |
| `--max-nudges N` | Wake-ups in a row before it switches itself off (the last is the note); 0 = never | 9 |
| `--find-me WORD` | Watch the chat whose record contains this fresh word (always use it) | |
| `--file PATH` | Which chat to watch | the most recently changed chat |

With a 5-minute cache (some API setups) use `--minutes 4`; that is only worth it for short breaks in
a huge chat.

## Safety facts (if the user asks)

It reads only a few labels from each entry of the chat's record: its kind (the user's message, your
reply, a tool result), whether your turn had ended, and its time. It never uses the chat's words; to
find its own chat it searches chats changed in the last 10 minutes for the one random word. If a long turn worries the user: each tool use
is its own short request that restarts the hour, so a turn that runs for hours keeps itself warm,
and Cache Saver times from the last request's start. The user's message, or anything that
wakes the chat while you are idle (another chat, a finished job), starts the count again, so loops
save with nobody at the keyboard; Cache Saver's own nudges and anything mid-work never do. It cannot help while you
are stuck inside ONE step that runs for over an hour (a very long command or helper agent): suggest
running such jobs in the background. When unsure, it errs toward nudging a little early,
not late. It writes two tiny
files per chat (in `~/.claude/cache-saver/`), sends nothing over the internet, and needs no
keys, passwords, or accounts. Free, MIT license.

## Make it automatic

If the user wants it on in every chat, offer to add this to their project's `CLAUDE.md`:

```markdown
## Cache Saver
At the start of every session, start Cache Saver (the cache-saver skill) as a background task.
Every time it finishes, do what its last line says. If it switched itself off, start it again the
next time anything wakes this chat (me, another chat, or a finished job). If I stopped it myself,
or I say I will be away for more than about 8 hours, leave it off.
```
