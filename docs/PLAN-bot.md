# Nifty Life staff bot — plan

The bot in `bot/` becomes the operator's single surface for the server: it answers questions about
Characters and Accounts, transcribes team voice discussions on demand, and performs the moderation
actions that today require opening the web admin area.

- **Vocabulary:** [CONTEXT.md](../CONTEXT.md) — the canonical terms.
- **Decisions:** [adr/](./adr/) — this plan reverses part of ADR-0007 and is recorded in ADR-0025.

## What the bot is today

One job, 380 lines, four files: mirror "who currently holds a staff role in Discord" into the `staff`
table, so `/admin` on the website knows who may enter. It approves nothing, asks nothing and holds no
permissions of its own beyond reading members. `bot/src/index.ts` has no interaction handler at all.

Everything below grows out of that. Nothing here replaces the mirror — it stays the first thing the bot
does, because the mirror is what makes the rest trustworthy.

## What was decided

- **Transcription source:** the team's own **Discord voice**, when the bot is pulled into the channel. Not
  Teamspeak. Player voice (ADR-0015) is explicitly out of scope and stays off the record.
- **Interface:** slash commands. No privileged intent beyond `GuildMembers` and `GuildVoiceStates`.
- **Write access:** the bot may ban, warn and resolve reports from Discord. This reverses the
  read-only posture ADR-0007 established, so it carries its own ADR and its own audit table.

## The blocker, and why Phase 0 exists

Discord made **DAVE** end-to-end voice encryption mandatory on every voice channel in **March 2026**.
`@discordjs/voice` 0.19.0 shipped DAVE support that does not work for receiving: bots enter reconnect
loops, `receiver.speaking` never fires, and audio packets fail with
`DecryptionFailed(UnencryptedWhenPassthroughDisabled)`. Worse than silence — the dropped packets
decode to noise, and Whisper confidently invents sentences out of it. A transcription feature that
hallucinates evidence is worse than no transcription feature.

The issue ([discordjs#11419](https://github.com/discordjs/discord.js/issues/11419)) was closed as fixed
in 0.19.2 with `@snazzah/davey` 0.1.12. Current versions as of 2026-10-12: `@discordjs/voice` 0.19.2,
`@snazzah/davey` 0.1.12, `discord.js` 14.27.0 (already installed).

That is a claim from an upstream changelog, not something this project has verified. So:

> **Phase 0 is a half-day spike and everything else waits for it.** Join a voice channel with
> `@discordjs/voice` 0.19.2 + davey 0.1.12, record ten seconds of one person speaking German, write a WAV,
> and run it through Whisper. If the words come back, the risk is gone and Phase 1 starts. If they do
> not, the fallback is py-cord 2.6.1, which reportedly handles DAVE correctly on the same channel — but
> that means a second bot process in Python, so we decide then, not now.

A fallback of last resort is Discord's own transcription, which is a human clicking a button and is not
something a bot can automate.

## Phase 1 — Transcriber

### The pipeline

```
Discord voice ──► @discordjs/voice ──► per-user Opus ──► prism-media Decoder ──► 48 kHz stereo PCM
                                                                                        │
                                                              ffmpeg -ar 16000 -ac 1     ▼
                                                                                    16 kHz mono WAV
                                                                                        │
                                                                    whisper -l de      ▼
                                                                                  German transcript
```

The valuable detail is **per-user capture**. Discord delivers each participant's audio as separate Opus
streams, so recording per user gives exact speaker attribution for free. No diarization, no guessing
who said the line that contradicts the witness. This is the single biggest reason the Discord-voice
route is better than a Teamspeak mixdown.

### Commands

| Command | What it does |
|---|---|
| `/record` | Joins the caller's current voice channel and starts capturing. Replies with who is in the call. |
| `/stop` | Stops capture, runs the pipeline, posts the transcript. |
| `/transcript` | Replays a stored transcript by id. |
| `/recordings` | Lists stored transcripts for a channel or a date range. |

Capture is **per speaker-turn**, not one long file: on `receiver.speaking` falling silent for ~1.5 s the
current segment closes, and a new one opens when that user speaks again. Segments are transkribiert
individually and merged in order, which keeps Whisper's timestamps aligned and keeps one bad segment
from poisoning a two-hour file.

### Storage

Migration `031_voice_transcripts.sql`: `voice_transcripts` (channel, guild, started_at, ended_at,
started_by, model, raw_text, duration_seconds) plus `voice_transcript_segments` (transcript_id,
speaker_discord_id, started_ms, ended_ms, text). Segments, not one blob — a transcript is only useful if
you can find the twenty seconds around the sentence in dispute.

Audio is deleted after transcription. It is kept only if the recording fails.

### Cost

Zero. Whisper runs locally, the models are MIT, and the bot is already a Node process on the operator's
own machine. No API key, no per-minute billing, nothing leaves the host. This is the whole reason for
running it locally rather than calling a hosted transcription service.

## Phase 2 — Player and Account lookups

Pure reads, no new writes, no new intents.

| Command | Returns |
|---|---|
| `/player <name or id>` | Character, Account, Discord ID, Teamspeak UID, Account status, Cash, jobs, property, vehicles, inventory summary, active bans |
| `/account <discord id>` | The Account behind a Discord ID, its status and its Character |
| `/online` | Who is connected right now, with Character and job |
| `/reports` | Open P&R and phone reports, oldest first |
| `/application <id>` | One application with its answers and its decision history |
| `/ledger <character>` | Recent ledger entries — where the money came from and went |
| `/sessions <character>` | Session history and total playtime |

`/player` is the command that replaces most of the "open the admin area and click through four screens"
work. Everything read here is read by the bot's **game account** (`nifty`, full privileges), which is
already the account in `bot/.env`. No grant changes are needed for Phase 2.

## Phase 3 — Moderation writes, and the audit table

The bot may now ban, warn and resolve reports from Discord. This is the part that needs the most care,
because it creates a **second writer** for tables the web admin already owns.

Migration `032_staff_actions.sql`: `staff_actions` (discord_id, action, target, reason, payload,
created_at, source = 'discord' | 'web'). Every write the bot performs writes one row here, in the same
transaction as the change itself. An unaudited moderation action on an RP server is not defensible
three months later, and a Discord bot is a worse audit story than a web form because the input is free
text from a chat client.

The boundary rules stay:

- The bot still **never** approves an Application. ADR-0007's one guarantee — the website and the bot
  together cannot self-approve — is not worth the convenience of a `/approve` command.
- Every ban and warn writes a `reason`, and a reason is mandatory.
- A ban issued from Discord is reversible from Discord, and the reversal is itself logged.

See ADR-0025 for what this reverses and why.

## Phase 4 — Push, so the bot works without being asked

| Event | Destination |
|---|---|
| New Application | Staff channel, with a deep link to the review page |
| New P&R or phone report | Staff channel |
| Account whitelisted but `teamspeak_uid IS NULL` | Staff channel — the player cannot talk and will not know why |
| Server up / down, player count crossing 50 % | Status channel |
| Last database dump older than 2 h | Owner only — ADR-0006 wants restore-tested dumps, and a watchdog is cheaper than finding out |

Detection is by polling the tables the bot can already read. A FiveM→bot bridge would be more elegant
and adds a new network surface and a shared secret to protect, which is a poor trade for tables that
change at human speed.

## Risks, honestly

- **DAVE.** Phase 0 exists for this reason and must not be skipped.
- **German RP jargon.** Characters have invented names, street names and department slang. Whisper will
  mangle them. Mitigation: segment-level transcription so one bad segment is visible and correctable,
  and a transcript is labelled as machine output, never as evidence on its own.
- **Hallucination on silence.** Whisper invents text when given noise. Segments are gated on an actual
  `speaking` event, and empty or near-silent segments are discarded rather than transcribed.
- **Recording consent.** Team members must know the bot records. It joins visibly, `/record` announces
  itself in the text channel, and the transcript names every participant. This is a staff-only channel,
  but it still gets said out loud in the team channel before first use.
- **CPU-only Whisper.** `torch 2.11.0+cpu` is installed — CUDA is not, despite an RTX 2070 SUPER being
  present. CPU transcription of `small` is roughly realtime on an i7-9700K, so a long staff call takes
  about as long as the call. Installing the CUDA build of PyTorch (~2.5 GB) would change that
  materially; that is a decision, not a detail, and it is not made in this document.
- **The bot holds the game account.** Full privileges on the whole schema. Every command is an
  opportunity to write with it. Phase 3's audit table exists partly because of this.

## What this does not change

- **ADR-0002** stays. No framework in the bot either — it stays hand-rolled TypeScript against
  `discord.js`, because the alternative is a dependency we would own forever for a bot that one person
  runs.
- **The staff mirror** stays the first thing the bot does and the only reason the website can answer
  "is this person staff" without holding a token.
- **In-game chat logging is not part of this plan.** The proximity chat in `nifty-chat` persists
  nothing, and a `chat_messages` table would be the foundation for in-game evidence review. It is worth
  doing, it is a separate piece of work, and nothing in this plan depends on it.