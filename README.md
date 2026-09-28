<div align="center">

<img src="assets/logo.png" alt="Cache Saver logo: an 8-bit Claude holding up a gold coin" width="140">

# Cache Saver

### (Cash Saver) for Claude Code

**Saves your cache. Saves your cash.**

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
![Setup: 1 minute](https://img.shields.io/badge/setup-1%20minute-blue.svg)
![No install](https://img.shields.io/badge/install-none-brightgreen.svg)
![Mac | Linux | Windows](https://img.shields.io/badge/works%20on-Mac%20%7C%20Linux%20%7C%20Windows-lightgrey.svg)
[![GitHub stars](https://img.shields.io/github/stars/OutletBoy/cache-saver?style=social)](https://github.com/OutletBoy/cache-saver/stargazers)

Keep your Claude Code chat warm while you step away,<br>
so your **5-hour window** and **weekly limit** last much longer.

## Up to 89% less usage when you come back from a break.

**Running autonomous loops? The savings multiply:** every chat that waits stays warm.

[Quick start](#quick-start-1-minute) · [How much you save](#how-much-you-save) · [Loops](#running-a-loop-with-several-chats-this-is-where-it-saves-the-most) · [How it works](#how-it-works) · [Just ask Claude](#just-ask-claude) · [FAQ](#faq)

</div>

---

> [!TIP]
> **The one rule:** coming back to Claude Code **within about 16 hours**? Leave it on. It always saves.
> Away **longer** (a weekend, a trip)? Turn it off before you go. **Forget? It switches itself off
> at the break-even point and leaves you a note saying why.** It can never cost you more than it saves.

---

## Quick start (1 minute)

**No install. No account. No settings.** Paste this into your Claude Code chat:

```text
Download https://raw.githubusercontent.com/OutletBoy/cache-saver/main/skills/cache-saver/SKILL.md and https://raw.githubusercontent.com/OutletBoy/cache-saver/main/skills/cache-saver/cache-saver.sh into ~/.claude/skills/cache-saver/, then read that skill and start Cache Saver.
```

That is the whole setup. Walk away. Claude keeps the chat warm until you come back.
From now on, in any chat, just say **"start the cache saver"** or **"stop the cache saver"**.

### Step 2 (recommended): make Claude follow the rule every time

Add this to your project's `CLAUDE.md` (the notes Claude reads at the start of every chat), or just
ask Claude to add it for you:

```markdown
## Cache Saver
At the start of every session, start Cache Saver (the cache-saver skill) as a background task.
Every time it finishes, do what its last line says. If it switched itself off while I was away,
start it again when I come back. If I stopped it myself, or I say I will be away for more than
about 16 hours, leave it off.
```

Now it is on in every chat, and Claude follows the 16-hour rule for you.

### Just ask Claude

The setup installs a small **skill** that teaches Claude everything about Cache Saver. So you never
need to come back to this page. Ask Claude things like:

- *"Should I leave Cache Saver on? I'm going to lunch / to bed / away for the weekend."*
- *"How much is Cache Saver saving me?"*
- *"How does Cache Saver work? Is it safe?"*
- *"Change Cache Saver to nudge every 50 minutes."*

---

## How much you save

The share of what coming back from a break would cost you, saved by Cache Saver:

| Your break | You save | Worth it? |
|---|:---:|:---:|
| Under 1 hour | still warm, not needed | - |
| **1 hour** (lunch) | **89%** | **YES** |
| **2 hours** (a meeting) | **83%** | **YES** |
| 3 hours | **78%** | **YES** |
| **4 hours** (an afternoon out) | **72%** | **YES** |
| 6 hours | **61%** | **YES** |
| **8 hours** (overnight) | **50%** | **YES** |
| 10 hours | **39%** | **YES** |
| 12 hours | 22% | yes, a little |
| 14 hours | 11% | yes, a little |
| 16 hours | about 0% | break-even |
| 20 hours | costs 22% more | turn it off |
| 24 hours | costs 50% more | turn it off |
| **A normal work day** (lunch + meeting + overnight) | **about 70%** | **YES** |

**Your first message back is about 18 times cheaper.** Bigger chats save more, because a cold
restart re-reads everything.

<details>
<summary><b>Where do these numbers come from?</b></summary>

<br>

Measured, not guessed. We read thousands of real Claude Code turns from our own long chats:

- Coming back to a **cold** chat re-saved the whole conversation. A typical 360,000-token chat
  re-saved about 333,000 tokens, at **double** the normal rate.
- A **warm** nudge only re-read it at **a tenth** of the rate, and saved about 650 new tokens.

So one cold restart costs about as much as **18 nudges**, using Anthropic's published cache rates.
That ratio holds for any chat size and any plan. Anthropic does not publish how many tokens one
percent of a subscription limit is, so savings are shown as a share of what the break would cost.

**On the pay-per-token API?** The same percentages apply to your bill. Multiply by your model's price
and your chat size to see it in dollars.

</details>

---

## Why it is worth it

**You already spent your limit building up that long chat. Cache Saver stops you paying for it twice.**

Claude Code keeps a saved copy of your chat, the **cache**, for about an hour. Step away longer and
your next message re-reads **everything**: every file, every plan, every fix. That is slow, and it takes
a big bite out of your limits right when you sit back down to work.

| | |
|---|---|
| **Your limits last longer** | Fewer "you have hit your limit" moments mid-work |
| **Instant answers when you return** | No waiting while Claude re-reads the chat |
| **1-minute setup** | One sentence. Nothing to install |
| **Tiny and safe** | One small file. No keys, no internet, only looks at times, never your chat's words |
| **Never late** | Times each hour from the moment Claude starts working, and leans early whenever it is unsure |
| **You always know it worked** | Each wake-up leaves one line in your chat: *"Cache Saver: kept your chat warm (wake-up 3 of 17)."* |
| **Never costs more than it saves** | Switches itself off at the break-even point and tells you why |
| **Claude knows it inside out** | Ask Claude when to use it, what it saves, or how to change it |
| **Free forever** | MIT license. Use it, change it, share it |

**Perfect for:**

- **Lunch breaks and meetings:** come back to a chat that answers instantly.
- **Overnight jobs:** a long test run finishes, and Claude can fix failures straight away.
- **Big codebases:** Claude has read dozens of large files; keeping that warm saves the most.
- **Teams of chats** (loop engineering): every long-running chat stays warm while it waits.
- **Anyone hitting their weekly limit:** a few avoided restarts a day add up, week after week.

---

## Running a loop with several chats? This is where it saves the most

**Loop engineering** means running several Claude Code chats as a team: one plans and supervises,
others build, others review, and they hand work to each other. It is powerful, and it quietly burns
usage, because **loop chats spend a lot of their time waiting**:

- the planner waits while a builder runs a long job;
- a reviewer waits for the next piece of work;
- the whole team waits for you while you are in a meeting or asleep.

Every chat that waits more than an hour goes cold, and **each one** pays a full restart when it wakes.
Loop chats are usually long, so those restarts are big. **Each chat has its own cache, so the savings
multiply with every chat you add.**

**Example: a 3-chat loop** (planner, builder, reviewer), where each chat waits 2 hours, 3 times a day:

| | Without Cache Saver | With Cache Saver |
|---|---|---|
| Cold restarts per day | **9 full restarts** | none |
| What the waits cost | 9 restarts' worth | about **1.5** restarts' worth of small nudges |
| Saved | | **about 83% of what those waits cost** |

Add an overnight wait for the whole team and the saving grows again.

**Great loop use cases:**

- **The supervisor or planner chat** that waits for workers to finish long builds or test runs.
- **Reviewer chats** that sit idle between pieces of work.
- **Chats waiting on you** for a decision while you are away from the keyboard.
- **Overnight runs**, where one chat works and the others wait for its result.
- **Long-lived "memory" chats** that hold the project's context and should never lose it.

**Skip it for:** short worker chats that do one job and close (they never wait), one-shot headless runs
(`claude -p`), and any chat that will wait more than about 16 hours.

**Setting it up for a loop:**

1. Put the [`CLAUDE.md` block](#step-2-recommended-make-claude-follow-the-rule-every-time) in the
   shared project, so **every** chat starts its own Cache Saver automatically.
2. That is it. Each chat finds and watches **its own** conversation (the skill uses the `--find-me`
   option), so chats never get mixed up.
3. A chat that is busy working is not quiet, so it is never nudged. You only pay for chats that are
   actually waiting.

---

## How it works

1. Claude runs Cache Saver as a **background task**.
2. It watches **when** Claude last started working in your chat (each entry in the chat file has a
   time on it). It only looks at those times, never at what the chat says.
3. 55 minutes after that start, if nothing new has happened, it stops, which wakes Claude up.
4. Claude replies with one line, **"Cache Saver: kept your chat warm (wake-up 3 of 17)."**, so you can
   see what happened while you were away. That reply refreshes the cache for another hour, and it
   starts again.
5. **Still away at the 17th wake-up (about 16 quiet hours)?** One more nudge would cost more than it
   could ever save. So instead of nudging, Cache Saver **switches itself off**, and that last wake-up
   is Claude leaving you a note for when you come back:

> *Cache Saver switched itself off after about 16 quiet hours, because leaving it on would have cost
> more than it saves. Your next message will re-read the chat once, and Cache Saver turns itself back on.*

6. **When you come back**, Claude turns it back on by itself and tells you in one line. No question
   to answer. It only stays off if **you** stopped it, or you say you are leaving for longer.

**Why stop there?** Every nudge is a small cost paid in case you come back soon; a cold restart is one
big cost. Cache Saver keeps paying the small cost only until the total reaches the big one, then
stops. That is the textbook best strategy when you cannot know how long someone will be away (the
classic "rent or buy" problem): if you come back, you saved; if you never do, the most you spent
extra is about one restart.

It sends nothing anywhere and needs no passwords, keys, or accounts.

---

## Things that can turn it off without you noticing

Cache Saver lives inside your Claude Code chat, so anything that stops the chat stops it too:

| What happens | What it means | What to do |
|---|---|---|
| **You close the chat, the terminal, or Claude Code** | It stops with the chat | Start it again in your next chat |
| **Your computer restarts, shuts down, or crashes** (including Windows updates) | It stops with everything else | Start it again after the restart |
| **Claude Code updates or restarts** | Same as closing it | Start it again |
| **Your computer goes to sleep** (lid closed, sleep mode) | Nothing can run while it sleeps, so the cache usually goes cold anyway | Keep the computer awake (plugged in, sleep off) during breaks you want covered |
| **Your internet drops** | The nudge cannot reach Claude, so the cache goes cold | Nothing; it works again when you are back online |
| **Claude asks you to approve the command** | The first run may ask permission, and it cannot restart until you answer | Choose "always allow" for the Cache Saver command once |
| **You hit your usage limit** | Claude cannot reply, so it cannot restart it | It comes back after your limit resets; start it again |
| **Claude waits on ONE step for over an hour** (a single very long command, or a helper agent that runs for hours) | Claude cannot send the nudge until that step ends, so the chat's cache can go cold meanwhile (the helper keeps its own cache warm) | Nothing needed for normal work: steps that each finish within an hour are fine. For very long jobs, run them in the background so Claude stays free |
| **The chat gets compacted** (`/compact`, or automatically when it gets very long) | Compacting can end background tasks | Ask Claude to start it again |
| **You start a new chat or use `/clear`** | It was watching the old chat | Start it again in the new one |
| **You run several chats at once** | Without the skill, it watches the chat that changed most recently | Use the skill (it finds its own chat automatically), or `--find-me` |

> [!TIP]
> **The easy fix for almost all of these:** add the `CLAUDE.md` block from
> [Step 2](#step-2-recommended-make-claude-follow-the-rule-every-time). Then Claude starts it again at
> the start of every new chat by itself. Not sure if it is running? Just ask Claude: *"Is Cache Saver
> on?"*

---

## FAQ

<details>
<summary><b>When should I NOT use it?</b></summary>

<br>

- You will be away **more than about 16 hours**: the nudges add up to more than one restart.
- You are **done with this chat** and will start a fresh one.
- The chat is **short**: re-reading it is cheap anyway.
- Your cache lasts only **5 minutes**: only worth it for short breaks in a huge chat (use `--minutes 4`).

</details>

<details>
<summary><b>Is it safe?</b></summary>

<br>

Yes. It looks at one file on your own computer, your chat's record, and uses only two things from each
entry: what kind it is (your message or Claude's reply) and its time. It never uses what the chat says,
writes only one tiny counter file per chat (in `~/.claude/cache-saver/`), opens no network connections,
and needs no credentials.

</details>

<details>
<summary><b>Does it work on Mac, Linux, and Windows?</b></summary>

<br>

Yes. `cache-saver.sh` runs on macOS, Linux, and Windows with Git Bash (which Claude Code uses on
Windows). `cache-saver.ps1` is included for Windows without bash.

</details>

<details>
<summary><b>Can I download it myself instead?</b></summary>

<br>

Yes. Copy the [`skills/cache-saver`](skills/cache-saver) folder into `~/.claude/skills/`, then tell
Claude *"start the cache saver"*. Or run the script without the skill:

```text
Run bash /path/to/cache-saver.sh as a background task. Every time it finishes, do what its last line says. Stop when I say "stop the cache saver".
```

On Windows with PowerShell only, use `powershell -File C:\path\to\cache-saver.ps1` instead.

| Option | What it does | Default |
|---|---|---|
| `--minutes N` (`-Minutes N`) | Quiet minutes before the nudge | `55` |
| `--max-nudges N` (`-MaxNudges N`) | Wake-ups in a row before it switches itself off; the last one is the note (0 = never) | `17` |
| `--find-me WORD` (`-FindMe WORD`) | Watch the chat whose record contains this fresh random word; finds the right chat even with several running | |
| `--file PATH` (`-File PATH`) | Which chat to watch | the most recent chat |
| `--help` | Shows the usage text | |

Set `--minutes` a few minutes below your cache lifetime. For a 1-hour cache, `55` is right.

</details>

<details>
<summary><b>Which chat does it watch?</b></summary>

<br>

The chat file in `~/.claude/projects` (or your `CLAUDE_CONFIG_DIR`) that changed most recently, which is
normally the one you are in. Running several chats at once? Pass `--file` to pick one. If it says
"no chat transcript found", pass the file directly with `--file`.

</details>

<details>
<summary><b>When does the hour start counting: when Claude starts replying, or when it finishes?</b></summary>

<br>

When Claude **starts** working on a message. The cache is read (and its hour restarted) at the very
beginning of each request, before any words stream back. So Cache Saver times from the **start**:
every entry in the chat's record carries a time, and it counts 55 minutes from the moment Claude's
last request went out, not from when the reply finished.

Does a long reply matter? Less than you might think. A long turn (say Claude works for 30 minutes,
or for 3 hours in a busy loop) is really many short requests, one after every tool it uses, and each
one restarts the hour. So while Claude is working, the cache stays warm by itself and Cache Saver
just keeps waiting; its clock only runs once Claude goes quiet. The last request usually starts
seconds before the turn ends: we measured over 60,000 real replies, and 99.9% finish within 2.3
minutes of starting. Timing from the start makes the rare slow one safe too.

It also knows the difference between **you** and Claude. Only a message you send counts as "you are
back". Claude's own replies and background jobs finishing do not, so the switch-off point stays right
even in a chat that keeps itself busy.

We also measured the hour itself: replies sent up to 60 minutes after the last one were always warm,
and every one after 62 minutes was cold. If it cannot read the times (an unusual setup), it falls back
to when the chat file last changed and nudges about 3 minutes early, so it still lands inside the hour.
A nudge a little early costs one tiny reply; a nudge late costs a full re-read, so it always picks early.

</details>

<details>
<summary><b>Is it tested?</b></summary>

<br>

Yes. `tests/run-tests.sh` checks the timing and the "are you back?" logic with made-up chat records:
slow replies, long turns, background jobs, error replies, older Claude Code versions, and the fallback.
It runs against both scripts and every way they can read the chat (`bash tests/run-tests.sh sh` or
`bash tests/run-tests.sh ps1`; needs GNU `date`, as on Linux or Git Bash).

</details>

<details>
<summary><b>How long does my cache last?</b></summary>

<br>

About an hour on Claude Code subscription plans. Check Claude Code's prompt-caching docs for your
setup. If unsure, the default of 55 minutes is the safe choice.

</details>

---

## Why I built this

I built Cache Saver for **loop engineering**: several Claude Code chats working together for hours,
one planning, others building. Their context is big, and a cold cache after a quiet hour meant slow,
expensive restarts. Cache Saver fixed that for me, so I am sharing it.

**If it saves you usage, give it a star** so other Claude Code users can find it.

---

<div align="center">

MIT licensed · Made by **OutletBoy** · Follow on X: [@outlet00](https://x.com/outlet00)

<sub>An unofficial fan project. Not made by, endorsed by, or affiliated with Anthropic. Claude and Claude Code are trademarks of Anthropic.</sub>

</div>
