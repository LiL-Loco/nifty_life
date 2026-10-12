# The Discord bot writes moderation actions, and audits them

The staff bot may ban, warn and resolve reports from Discord. It still may not approve an
Application. Every action it writes is recorded in a `staff_actions` table by the same transaction that
performs it.

This reverses the posture [ADR-0007](./0007-discord-whitelist-tier1-manual-review.md) established and
partly revised on 2026-10-11, where the approval button in Discord was deliberately replaced by the web
admin area. The reversal is recorded here rather than absorbed quietly.

## Why this and not read-only

The web admin area is the better place to make a decision. It is also a browser, and the decisions that
need making fastest are the ones where the context is a voice call with the team. A moderator who has
just been told "that is the third report this week" should not have to open a site, log in, find the
report and find the character — the cost of the detour is the reason people let things sit.

Read-only-plus-deeplinks was the right default and stays the default for everything that is not urgent.
Bans, warns and report resolutions are the narrow set where the friction was measurably costing
response time.

## What the bot still may not do

- **It may not approve, reject or otherwise decide an Application.** This is the one guarantee ADR-0007
  exists to hold, and the one the whole grant structure in `database/grants.sql` is built around. A bot
  that could approve would be a second path to membership, and the whitelist is the thing the whole
  server's identity rests on. Not worth the convenience.
- **It may not write to `staff`.** That table stays mirrored from Discord roles and nothing else, so
  there is exactly one mechanism by which somebody becomes staff.
- **It may not touch `characters` beyond what a moderation action needs.** Renaming a Character stays a
  game-server operation.

## Why the audit table is not optional

A moderation action taken from a chat client has three properties that make an audit mandatory rather
than tidy:

1. **The reason is free text typed under time pressure.** A ban with no reason is not defensible, and a
   ban with a vague reason is not much better.
2. **There are now two writers.** The web admin already owns these tables. Two writers means the
   question "who did this and when" has two answers, and the only way to answer it is a table neither of
   them can quietly bypass.
3. **It is the operator's own team.** One person is the entire staff. An audit of your own actions is
   still worth having — the failure mode is not a malicious moderator, it is remembering in three
   months what happened during a call at 2am.

`staff_actions` is written in the same transaction as the action. An action that succeeded but was not
logged does not exist as far as the audit is concerned, which is the correct direction to fail: fewer
things recorded, never a recorded thing that did not happen.

## Consequences

- The bot connects with the **game account** and can write to the whole schema. Every command is an
  opportunity to misuse that. Narrow commands, mandatory reasons and the audit row are the mitigations;
  a scoped DB account for the bot would be stronger and is not built now.
- Bans issued from Discord are reversible from Discord, and the reversal is itself an audited action.
  `bans` has no soft-delete; a reversal writes a new row, so the history stays legible.
- The web admin and the bot can disagree about the state of a report. Both read the same row, so
  divergence is a rendering problem, not a data problem.
- If the bot's token is ever exposed, the blast radius is now larger than "who is staff". It can ban
  players. The token is in `.env`, never in the repo, and resetting it is one Developer Portal click.