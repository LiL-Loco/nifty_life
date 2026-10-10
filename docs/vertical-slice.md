# Vertical slice — connect → character → job → earn → buy → reconnect

The first thing in this project that is meant to be **run**, not proven by a
schema test. Everything before this was parse-checked and SQL-verified; nothing
before this had ever been executed by an FXServer.

## Why this exists

Layers 1–5 built a set of modules that all worked in isolation and none of which
anything could actually reach. Money, inventory and jobs were pushed to the
client over events that **no client file listened for**, and no player action had
a net event at all. The systems existed; the game did not.

So the slice is deliberately boring: connect, get money, work, spend it, come
back. Everything it touches is already built. What is new is the wiring, and the
wiring is where the bugs live.

## The path

| Step | What happens | Code |
|---|---|---|
| 1 | `playerConnecting` → Discord whitelist | `server/sv_main.lua` |
| 2 | `nifty:server:ready` → character loaded or creator opened | `server/sv_main.lua` |
| 3 | `enterWorld` → money, inventory, jobs, shop all pushed | `server/sv_main.lua` → `client/cl_world.lua` |
| 4 | Join a job | `nifty:server:jobJoin` → `Jobs.join` |
| 5 | Start a shift (payslip fee) | `nifty:server:dutyStart` → `Jobs.startDuty` |
| 6 | End a shift (pro-rated wage) | `nifty:server:dutyEnd` → `Jobs.endDuty` |
| 7 | Buy something | `nifty:server:buy` → `Shop.buy` |
| 8 | Reconnect — everything above is still there | ADR-0004 |

## How to run it

```
# 1. copy the config and fill in the connection string
Copy-Item server.cfg.example server.cfg

# 2. MariaDB — the schema is applied by the entrypoint in filename order
docker run --name nifty-db -e MARIADB_ROOT_PASSWORD=dev -e MARIADB_DATABASE=nifty_life `
  -p 3306:3306 -v "${PWD}/database/migrations:/docker-entrypoint-initdb.d:ro" -d mariadb:11

# 3. FiveM
FXServer.exe +exec server.cfg
```

## Manual test script

Work through this in order. Each step has a **pass condition** that can only be
met if the server, not the client, is telling the truth.

**Setup** — whitelist your own Discord ID first, otherwise step 1 ends at a kick
screen and you will be debugging the wrong thing.

1. **Connect.** You land in the world with `0,00 $` bank and a phone + ID card in
   your inventory.
   *Pass:* the HUD shows cash and bank. `/niftystate` prints the same numbers.

2. **Reconnect immediately.** Quit and rejoin.
   *Pass:* same balance, same two items. Nothing was reset, nothing duplicated.

3. **Open the jobs panel (F3).** You see all eight jobs with placeholder wages.
   *Pass:* all eight are listed, including the ones you have never joined.

4. **Join `taxi`.** *Pass:* the button changes to "Schicht beginnen".

5. **Start a shift.** Cash drops by the payslip fee (25.00).
   *Pass:* HUD cash is exactly 25.00 lower. `ledger` has a `job_wage` row.

6. **End the shift immediately.**
   *Pass:* you are told how long you worked and that you earned **0.00**. The
   shift is under `job.duty.min_seconds`, and being told the number is the point
   — a silent zero looks like a bug.

7. **Start a shift, wait ~5 minutes, end it.**
   *Pass:* you are paid roughly `wage × minutes / 60`. Cash is higher than after
   step 5 by more than the payslip cost.

8. **Open the shop (F2) and buy bread (12.00).**
   *Pass:* cash drops by 12.00, inventory gains one `bread`.

9. **Try to buy a second `phone_sim` (50.00) with 463.00 cash.**
   *Pass:* refused with "insufficient funds", balance untouched.

10. **Sell the bread back.** *Pass:* cash rises by 6.00 (half price). Bread is gone.

11. **Open the inventory (F1).** *Pass:* slots and weight are shown, and the
    weight figure matches `quantity × unit weight`.

12. **Open a second client and run step 5.**
    *Pass:* both sessions pay out independently; neither sees the other's balance.

## What this does **not** prove

Being blunt about it, because the alternative is a false sense of coverage:

- **The charge/refund ordering in `Shop.buy` is unverified.** "Charge first,
  refund on delivery failure" is Lua logic and the schema harness cannot execute
  it. It needs a test that fills an inventory to capacity and then buys — the
  one path where the refund fires. Until that exists, the refund is a claim.
- **No NUI frame has been rendered.** The HTML, CSS and JS parse, and the message
  contract matches the Lua side by inspection. Nobody has seen the panel.
- **Collection natives, ped setup and teleports have still never run.**

## Known rough edges

- The jobs panel shows wages but the roster has no ordering by pay, which is the
  only thing a new player compares.
- There is no way to join a job from anywhere except the jobs panel — no NPC, no
  job board. Fine for a slice, wrong for a launch gate.
- Property and vehicle panels are wired on the server but **have no UI at all**.
  `nifty:server:properties` and `nifty:server:myVehicles` fire into nothing.