# Discord-OAuth whitelist, Tier 1 coupling, manual review

Applicants authenticate through Discord OAuth, so we receive a verified Discord ID rather than one typed
into a form. Applications are reviewed by a human — never auto-approved. The website is coupled to the
game server at **Tier 1 only**: it submits applications and displays their status, and nothing else.

## The coupling boundary

- **Tier 1 (adopted):** the website inserts application rows and reads its own application status. The game
  server reads the whitelist at `playerConnecting`.
- **Tier 2 (deferred):** exposing live game state — character money, property, job history — on the
  website. Deferred because it adds a second security surface over player tables and nothing in the launch
  gate requires it.
- **Tier 3 (rejected):** modifying game state from the web. That is a second admin panel without txAdmin's
  protections, and the attack surface is unacceptable for a solo-maintained server.

Two database users enforce this in the engine rather than in application code: `fivem` with full access for
the game server, and `website` restricted to inserting into the applications table. **The website can
submit; it can never approve.** A compromised website bug therefore cannot read or alter player data.

Applications are reviewed inside Discord via a small bot that posts pending applications to a staff
channel with approve/reject buttons. The site is the only piece a player touches; you never log into a
separate admin page to process applications.

## Consequences

- Manual review is a permanent staffing commitment. There is one reviewer, and it is also the entire
  moderation team (launch-gate item 21).
- The application needs a real state machine — submitted → under review → approved / rejected — because
  players will check status and you will need to keep that honest.
- The Discord ID is the whitelist identity. Because FiveM reports the player's real identifiers at connect,
  an entry can only ever match the account that genuinely owns it; no impersonation path exists.
- Tech stack: Node/TypeScript across both the website and the Discord bot, one language, and the stack we
  already write professionally.