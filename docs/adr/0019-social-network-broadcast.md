# Social network is a broadcast timeline, admin-only deletion

The in-game social network ("Peeper", after the Alternate-Life reference) is a broadcast feed in the
Twitter/X mould: asymmetric follows, a public timeline, replies and likes. It is not a mutual-friends
graph.

## Deletion is staff-only

**A character cannot delete their own post.** Only an admin can remove one. In roleplay you do not get to
rewrite your own history.

This is the authentic choice, but it makes moderation *reactive* rather than proactive — which is the
whole of the design's risk on a server where one person is simultaneously the developer, the admin and
the entire moderation team.

## Consequences

- **A report function and staff search are prerequisites, not extras.** With permanent, admin-only
  deletion, the only way a problem reaches staff is a player pressing report. Without a search by
  character, keyword or date, a report is unactionable — "this person posted something awful in March"
  cannot be answered by scrolling a six-month timeline. Deletion rights are only half the feature;
  discovery is the other half.
- **Staff deletion writes a moderation record** — actor, timestamp, reason. Not to undo the decision, but
  because "why did staff remove this?" gets asked by the author, and having the answer beats guessing.
- **Places are an attribute, not a tracker.** A post may carry a named location. There is no live "who's
  here now" list and no location history. Full Peeper parity was rejected because check-ins would make a
  permanent, non-removable record of where every character was — on a server with no deletion rights and
  one moderator. It also gives players the part that actually matters socially ("look where I am") for a
  fraction of the permanent data.
- ADR-0004 is **not** extended to social content. It was decided about property, vehicles and money, where
  losing something would hurt. A post is closer to speech: players expect their own deletions to work, and
  an unremovable archive authored by strangers is the largest operational liability in the design.
- Social content is untrusted client input like everything else (ADR-0007): post length, author identity,
  reply targets and attached Places are all resolved and checked server-side before a row is written.