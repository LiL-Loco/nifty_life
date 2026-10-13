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

## Phase 0 — does the bot actually hear anything?

Half a day, and the rest of the plan waits for it. The spike (`bot/src/spike/voice-spike.ts`) joins a
voice channel, records, and writes one WAV per captured segment.

**Status 2026-10-13 — two of three questions answered, and they are the ones that decide.**

**Answered: transcription works, and VAD does not invent text.** Measured on this machine with
`small`/int8 on the i7-9700K, against German test audio generated in Discord's own PCM shape
(48 kHz, 16-bit, stereo):

| Case | Result |
|---|---|
| German speech, 15.7 s | 2 segments, 2.5× realtime, word timestamps present |
| Digital silence, 10 s | empty, RMS 0 |
| Low-level noise, 10 s | empty |
| Speech + 10 s trailing silence | stops at 15.0 s of 25.7 s — trailing silence produced nothing |

Two honest caveats about that table. First, with `small` the **vad=OFF** column also produced nothing
on silence and noise, so this run showed that VAD behaves correctly but did *not* reproduce the
hallucination it exists to prevent. Hallucination propensity is model-dependent and larger models are
the worse offenders — so **the table has to be re-run with `turbo` before shipping**, and the `turbo`
result is the one that decides. Second, vocabulary is the real weakness: "Vinewood" came back as
"Weinwut" and "Pillbox" as "Pilbocks". Correct sentences, invented proper nouns — which is precisely
what a server's own invented geography is made of.

The HTTP service (`bot/transcriber/service.py`) is built and exercised: 401 without a token, German
transcription over the wire, word-level timestamps in the response, silence empty at RMS 0.

**Still open: does audio arrive at all?** The spike is written and compiles; it has not been run
against Discord. If it comes back silent, the one question worth asking first is whether the bot's
**Connect** and **Speak** permissions are granted on that channel — a bot that joins deaf receives
nothing, which looks identical to a broken capture path.

### Implementation notes, not decisions

Discord encrypts voice end-to-end, and the library version that handles it correctly is pinned in
`bot/package.json`. There is an upstream issue history worth knowing about
([discordjs#11419](https://github.com/discordjs/discord.js/issues/11419)) because the wrong version
produces noise rather than silence, and noise is what Whisper turns into invented sentences. That
failure mode is why Phase 0 exists at all — but it is a build-time detail, not something an operator
has to reason about. It lives in LEARNINGS.md with the other two findings from building the spike: the
`speaking` event moving to `SpeakingMap` in 0.19.x, and `opusscript` standing in for an opus native
build that does not compile on this machine.

## Phase 1 — Transcriber

### The pipeline

```
Discord voice ─► @discordjs/voice ─► per-user Opus ─► prism-media Decoder ─► 48 kHz stereo PCM
                                                                                   │
                                                                     WAV header written here
                                                                                   ▼
                                                                            48 kHz stereo WAV
                                                                                   │
                                          faster-whisper service, localhost, int8 on CPU
                                          PyAV decodes and resamples to 16 kHz mono,
                                          Silero VAD strips silence before the model sees it
                                                                                   ▼
                                                             [{ start, end, text, words }, …]
```

### Why faster-whisper and not openai-whisper

Chosen 2026-10-12 over the `openai-whisper` pip package that was already installed, and it is not a
close call:

- **No PyTorch.** It runs on CTranslate2, which has its own kernels. The installed `torch 2.11.0+cpu`
  is not used, and no CUDA build of PyTorch is needed — which removes a ~2.5 GB download that was
  otherwise on the table purely to unblock transcription.
- **Silero VAD is built in.** `vad_filter=True` drops non-speech before inference. Silence is the input
  that makes Whisper hallucinate, so this attacks the failure at its source instead of hoping a
  threshold downstream catches it. The default only removes silence longer than 2 s;
  `vad_parameters=dict(min_silence_duration_ms=500)` suits segment-based capture better.
- **Roughly twice the CPU speed** of openai-whisper at equal accuracy, and `int8` is supported on CPU
  directly.
- **Word-level timestamps** are available, which is what makes a transcript navigable to the second
  that matters.
- **No separate ffmpeg step.** PyAV decodes and resamples to the 16 kHz mono Whisper needs, so the
  recorder writes a 48 kHz stereo WAV and hands the file over.

`turbo` (large-v3-turbo) is the model to start on: it is close to large-v3 quality at a fraction of the
cost, and German is well represented. `small` is the fallback if throughput turns out to matter more
than vocabulary.

### The transcriber service

faster-whisper is a Python library, and the bot is Node. It runs as a small local service,
`bot/transcriber/service.py`, listening on `127.0.0.1` with a token from the environment:

- the model is loaded **once** at startup and stays warm, which matters because a model load costs
  seconds and every `/stop` would otherwise pay it again;
- `POST /transcribe` takes a WAV path and returns segments as JSON, with `vad_filter`, `language=de`,
  `word_timestamps` and `beam_size` as parameters;
- it binds to loopback only. It never listens on a network interface, and the token exists so that a
  stray local process cannot feed it arbitrary files.

No framework and no dependency beyond `faster-whisper` itself: `http.server` is in the standard
library, and the same "we own this forever" trade ADR-0002 already makes applies to a two-file HTTP
wrapper.

### Why per-user capture is the point

Discord delivers each participant's audio as a separate Opus stream, so recording per user gives exact
speaker attribution for free. No diarization, and no guessing who said the line that contradicts the
witness. This is the single biggest reason the Discord-voice route is better than a Teamspeak mixdown —
and it is why faster-whisper's absence of built-in diarization does not matter here.

### Commands

| Command | What it does |
|---|---|
| `/record` | Joins the caller's current voice channel, starts capturing, and remembers who asked and where. Replies with who is in the call. |
| `/stop` | Stops capture early and runs the pipeline. A convenience — leaving also stops it. |
| `/transcript` | Replays a stored transcript by id. |
| `/recordings` | Lists stored transcripts for a channel or a date range. |

### Capture is per speaker-turn, not one long file

On `receiver.speaking` falling silent for ~1.5 s that speaker's current segment closes and the next one
opens when they speak again. Each segment becomes a WAV, each is transcribed on its own, and the results
are merged in time order. This keeps Whisper's timestamps aligned with real speech, keeps one bad
segment from poisoning a two-hour file, and gives a per-speaker split for free — which is the other half
of why per-user capture is worth doing.

The bot does not own its own lifecycle in the channel. **Whoever fetched it in can take it out again,
and that is the normal way a recording ends.** So the trigger to stop is the loss of the bot's voice
session, not a command:

```
IDLE
  └─ /record in text channel T while in voice channel V  →  remembers invoker U and channel T
RECORDING
  ├─ bot loses its voice session (disconnected, kicked, moved, server shutting down) → STOPPING
  ├─ /stop                                                                    → STOPPING
  └─ nobody has spoken for RECORD_IDLE_MINUTES                                 → STOPPING
STOPPING
  ├─ close every open per-speaker segment and write the WAVs
  ├─ under AUDIO_FLOOR_MINUTES of speech? delete and return to IDLE without posting
  ├─ "Transcribing…" — the interaction is deferred, not left hanging
  ├─ call the faster-whisper service once per speaker
  └─ deliver the result to U                                                   → IDLE
```

The session loss is detected two ways because either one alone has a blind spot: discord.js fires
`voiceStateUpdate` with the bot's session set to `null`, and the connection reports
`VoiceConnectionStatus.Destroyed`. A person joining or leaving the call is **not** a stop signal, and a
second `/record` while already recording is refused rather than silently joined to the first.

Three guards that exist because this bot is on a machine with a disk:

- **Segments are written to disk as they close**, not held in memory. A crash or a `Ctrl-C` at minute
  ninety should cost the current segment, not the whole call.
- **A wall-clock ceiling** (four hours) stops a forgotten bot from filling the disk. It stops cleanly and
  transcribes what it has.
- **An idle timeout.** A bot sitting in a channel nobody used it in is worse than one that left.

### Delivering a transcript that does not fit in a message

Discord caps a message at 2000 characters, and an hour-long staff call is comfortably five times that.
Chunking into numbered messages is unreadable, so delivery is split by audience:

- **The invoker gets the full text as a direct message**, with the transcript attached as a file and
  per-speaker sections with timestamps. Short enough, it is also inlined.
- **The staff channel gets only a notice**: voice channel, who was in it, wall-clock duration, actual
  speaking time, speaker count, and the `/transcript` command to pull the rest.

The split is deliberate rather than cautious. The transcript is one person's view of a conversation
that other people were in, and the team has no business reading it casually — but the team does need to
know a recording happened and what it covered, because "nobody recorded that call" is exactly the gap
this feature exists to close. Content goes to the person who asked for it; the fact of it goes to the
channel.

The full text is stored either way, so `/transcript` can replay it later without a second transcription
run.

**If the invoker has closed their DMs**, the direct message fails with a Discord error and the transcript
has to go somewhere. In that case the full file is attached to the staff-channel notice instead, and the
notice says why. Silent failure here would be the worst outcome: a recording that exists, that nobody
was told about, and that nobody can find.

### Storage

Migration `031_voice_transcripts.sql`: `voice_transcripts` (channel, guild, started_at, ended_at,
started_by, model, raw_text, duration_seconds) plus `voice_transcript_segments` (transcript_id,
speaker_discord_id, started_ms, ended_ms, text). Segments, not one blob — a transcript is only useful if
you can find the twenty seconds around the sentence in dispute.

Audio is deleted after transcription. It is kept only if the recording fails.

### Cost

Zero. faster-whisper is MIT, the weights are downloaded from the Hugging Face Hub once, and everything
runs on the operator's own machine. No API key, no per-minute billing, nothing leaves the host. This is
the whole reason for running it locally rather than calling a hosted transcription service, and it is
also why a hosted one is not being reconsidered at Phase 2.

One caveat worth stating plainly: the models are downloaded on first use, and `turbo` is a ~1.6 GB
fetch. That is a one-time disk cost, not a licence cost.

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

- **Unverified capture.** The bot has never received a packet from Discord. Until the spike runs
  against a live channel, "the bot can hear" is an assumption. If it comes back silent, check the
  channel's **Connect** and **Speak** permissions before suspecting the code.
- **German RP jargon.** Characters have invented names, street names and department slang. Whisper will
  mangle them. Mitigation: segment-level transcription so one bad segment is visible and correctable,
  and a transcript is labelled as machine output, never as evidence on its own.
- **Hallucination on silence.** Whisper invents text when given noise. Two independent guards: a segment
  is only opened by an actual `speaking` event, and Silero VAD runs before inference with the threshold
  tuned for short gaps. Phase 0 verifies the second one on purpose, because it is the guard that is
  supposed to be doing the work and it is the one that fails quietly.
- **Recording consent.** Team members must know the bot records. It joins visibly, `/record` announces
  itself in the text channel, and the transcript names every participant. This is a staff-only channel,
  but it still gets said out loud in the team channel before first use.
- **CPU throughput.** No GPU is involved: faster-whisper does not use PyTorch, so the installed
  `torch 2.11.0+cpu` and the idle RTX 2070 SUPER are both irrelevant to this feature. `int8` on the
  i7-9700K is the configuration. A long staff call may take longer to transcribe than it took to
  happen — which is fine for an on-demand `/transcript`, and is the reason this is not a live-caption
  feature. The RTX card could run CTranslate2 on CUDA with cuBLAS 12 and cuDNN 9 installed separately,
  and that remains available as a later speed-up if throughput ever matters.
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