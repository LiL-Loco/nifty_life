# Peeper is reachable from the website, bound to the character

The social network (ADR-0019) is available on the website for anyone logged in with Discord. A post is
authored by a **character**, whichever surface it was written on. There is no separate web identity.

## The problem this had to solve first

ADR-0019 describes an **in-game** network and builds its entire moderation model on that: posts have a
character as author, only staff may delete, staff search by character, and author identity is resolved
server-side. Extending the surface to a website does not add a UI problem — it adds an **identity**
problem, and it was worth solving before writing any of the website.

The obvious implementation — the website posts under the logged-in Discord account — is wrong, and wrong
in the way that costs the most. It gives every player **two authors**. A post deleted in-game reappears on
the web minutes later under an identity moderation cannot tie to the first one, a ban covers one half, and
"only admins delete" stops being a statement about a person and becomes a statement about an account.
ADR-0019 already names permanent, staff-only deletion as the design's central risk; this would have
multiplied that risk by the number of surfaces rather than reduced it.

## The binding is proven, not asserted

A Discord login and a character are linked by a code **generated in game** and **typed on the website**.
Neither side alone is sufficient: holding the Discord account does not let you claim a character, and
holding a character does not let you link an account without showing the code.

The handshake is three tables, split by who writes them:

| Table | Written by | Contains |
|---|---|---|
| `web_pairing_codes` | game server only | character → SHA-256 of the code, expiring, single-use |
| `web_link_requests` | website, INSERT only | Discord ID + the typed code |
| `web_links` | game server only | the proven Discord ↔ character binding |

The split exists so that **the website still has no UPDATE anywhere**. Confirmation is the game server's
capability and nobody else's — the same property that makes ADR-0007's application approval impossible for
the website. If the website could UPDATE `web_link_requests`, it would mark its own request confirmed and
link itself to any character, and none of the code around it would notice.

Codes are stored hashed, so a database dump cannot be replayed against the website. Requesting a new code
supersedes the old one rather than shadowing it — a player asking for a replacement is telling you the
previous code is compromised.

## Consequences

- **The website cannot author a post on its own initiative.** Every write goes through `web_links`. The
  known gap is recorded in `database/grants.sql`: `INSERT ON peeper_posts` does not by itself constrain
  `author_character` to a linked character, so the website must resolve the author in its own transaction.
  The clean fix is a stored procedure taking the Discord ID, and it is written down rather than left as a
  comment in someone's head.
- **Pairing only completes while the game server is running** (ADR-0010 — the world is frozen Monday to
  Thursday). A request made midweek is accepted on Friday. Codes expire in 15 minutes, so the website has
  to say so rather than accept a code and appear to hang.
- **Posts snapshot the author's display name.** This is not denormalisation for its own sake: it is what
  lets the website render a feed with **no grant at all on `characters`**, and it is the semantically right
  answer besides — a post reads as the name it was published under.
- **Deletion stays in the game.** Staff are people playing the server, so soft deletion remains a
  game-server capability and the website keeps its no-UPDATE, no-DELETE grant set.
- **This adds to the blocked path, it does not unblock it.** The website still does not exist and is still
  blocked on a Discord Developer Application (launch-gate items 23, 29). What this ADR settles is the
  schema and the privilege boundary behind it, both of which had to be right before the first line of
  website code is written.

## The one place the boundary is weaker than the rest

`SELECT ON web_links` returns every Discord-to-character mapping, not only the caller's own. The website
is expected to filter on its own session in application code — which is weaker than the privilege boundary
everywhere else in `database/grants.sql`. The remedy, if it is ever needed, is a row-filtered view keyed on
a session variable in place of the table grant. Recorded here rather than left implicit, because the whole
point of this file is that the weak spots are written down.