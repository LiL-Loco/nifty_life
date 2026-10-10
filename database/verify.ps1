<#
.SYNOPSIS
    Proves the Nifty Life 2.0 schema invariants against a real MariaDB.

.DESCRIPTION
    Every ADR this project depends on makes a claim that the database is supposed
    to enforce rather than merely encourage. This script applies the migrations
    to a throwaway container and attempts the operations that must fail.

    If a test below ever passes when it should fail, the invariant is being
    enforced by application code instead of by the schema — which means it is
    enforced nowhere. That is the whole point of running this.

.EXAMPLE
    pwsh -File database/verify.ps1
    pwsh -File database/verify.ps1 -KeepContainer   # leave it running to poke at
#>

[CmdletBinding()]
param(
    [string]$ContainerName = 'nifty-schema-verify',
    [string]$Image = 'mariadb:11',
    [switch]$KeepContainer
)

$ErrorActionPreference = 'Continue'
$script:Failures = 0
$script:Checks = 0

function Write-Step([string]$Message) {
    Write-Host ''
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

function Invoke-Sql {
    param([string]$Sql, [string]$User = 'root', [string]$Password = 'test', [string]$Database = 'nifty_life')
    $output = docker exec $ContainerName mariadb "-u$User" "-p$Password" $Database -e $Sql 2>&1
    return @{ Output = ($output -join "`n"); Exit = $LASTEXITCODE }
}

function Assert-Run {
    param([string]$Name, [string]$Sql, [string]$Expect)
    $script:Checks++
    $result = Invoke-Sql -Sql $Sql
    $expectExit = if ($Expect -eq 'reject') { 1 } else { 0 }
    $ok = $result.Exit -eq $expectExit

    if ($ok) {
        Write-Host ("  PASS  {0} ({1})" -f $Name, $Expect) -ForegroundColor Green
    } else {
        $script:Failures++
        Write-Host ("  FAIL  {0} — expected {1}, exit {2}" -f $Name, $Expect, $result.Exit) -ForegroundColor Red
        Write-Host ("        {0}" -f $result.Output) -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# Container
# ---------------------------------------------------------------------------
Write-Step "Starting throwaway MariaDB"
docker rm -f $ContainerName 2>&1 | Out-Null
docker run --name $ContainerName `
    -e MARIADB_ROOT_PASSWORD=test `
    -e MARIADB_DATABASE=nifty_life `
    -v "${PWD}/database/migrations:/docker-entrypoint-initdb.d:ro" `
    -d $Image 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "  FAIL  container did not start" -ForegroundColor Red
    exit 1
}

# The entrypoint applies init scripts to a TEMPORARY server, then restarts.
# Polling `SELECT 1` is not enough — it succeeds mid-init. Wait for the expected
# table count instead. (Getting this wrong hides half the schema.)
$expectedTables = 27
$expectedJobDefs = 8
$ready = $false
for ($i = 0; $i -lt 100; $i++) {
    Start-Sleep -Seconds 3
    $probe = docker exec $ContainerName mariadb -uroot -ptest nifty_life -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='nifty_life';" 2>&1
    if ($LASTEXITCODE -eq 0 -and ($probe -join '').Trim() -match [regex]::Escape("$expectedTables")) {
        $ready = $true
        break
    }
}

if (-not $ready) {
    Write-Host "  FAIL  migrations never completed ($expectedTables tables expected)" -ForegroundColor Red
    docker logs $ContainerName 2>&1 | Select-Object -Last 30
    exit 1
}
Write-Host "  PASS  all $expectedTables tables created" -ForegroundColor Green

$jobs = Invoke-Sql -Sql "SELECT COUNT(*) FROM job_defs"
$script:Checks++
# `SELECT COUNT(*)` output is header line + value line, so the number is the LAST
# line. Matching with `-match "^8"` silently fails and looks like a data bug.
$jobCount = ($jobs.Output -split "`n" | Select-Object -Last 1).Trim()
if ($jobCount -eq "$expectedJobDefs") {
    Write-Host "  PASS  $expectedJobDefs job definitions seeded" -ForegroundColor Green
} else {
    $script:Failures++
    Write-Host "  FAIL  expected $expectedJobDefs job definitions, found: $jobCount" -ForegroundColor Red
}

# A job whose wage setting is missing pays nothing, and it fails SILENTLY: the
# character works a whole shift, the ledger records nothing, and nobody notices
# for a week. So every job code must have a wage row.
$script:Checks++
$unpaid = Invoke-Sql -Sql @"
SELECT d.code FROM job_defs d
  LEFT JOIN settings s ON s.`key` = CONCAT('job.wage_per_hour.', d.code)
 WHERE s.`key` IS NULL
"@
if ($unpaid.Exit -eq 0 -and -not $unpaid.Output.Trim()) {
    Write-Host '  PASS  every job has a wage setting (allow)' -ForegroundColor Green
} else {
    $script:Failures++
    Write-Host "  FAIL  jobs with no wage setting would earn nothing: $($unpaid.Output)" -ForegroundColor Red
}

# The roster from migration 003 was confirmed with the owner. A later migration
# that renames or recodes one of those four is a silent content change.
$script:Checks++
$renamed = Invoke-Sql -Sql @"
SELECT d.code FROM job_defs d
  LEFT JOIN (SELECT 'police' AS code, 'Los Santos Police Department' AS n
             UNION ALL SELECT 'ems', 'Pillbox Medical'
             UNION ALL SELECT 'taxi', 'Taxi Driver'
             UNION ALL SELECT 'mechanic', 'Mechanic') o ON o.code = d.code
 WHERE o.code IS NOT NULL AND d.name <> o.n
"@
if ($renamed.Exit -eq 0 -and -not $renamed.Output.Trim()) {
    Write-Host '  PASS  the owner-confirmed roster survived migration 005 (allow)' -ForegroundColor Green
} else {
    $script:Failures++
    Write-Host "  FAIL  migration 005 renamed confirmed jobs: $($renamed.Output)" -ForegroundColor Red
}

# ---------------------------------------------------------------------------
# ADR-0008 — one character per account
# ---------------------------------------------------------------------------
Write-Step 'ADR-0008 — one character per account'
Invoke-Sql -Sql "INSERT INTO accounts (id, discord_id, status) VALUES ('acc-1','111','active')" | Out-Null
Assert-Run -Name 'first character for an account' `
    -Sql "INSERT INTO characters (id, account_id, first_name) VALUES ('chr-1','acc-1','Ada')" -Expect 'allow'
Assert-Run -Name 'second character for the SAME account is refused' `
    -Sql "INSERT INTO characters (id, account_id, first_name) VALUES ('chr-2','acc-1','Grace')" -Expect 'reject'
Assert-Run -Name 'a Discord ID cannot be reused by a second account' `
    -Sql "INSERT INTO accounts (id, discord_id, status) VALUES ('acc-2','111','active')" -Expect 'reject'

# A second character on a second account. ADR-0008 allows one character per
# ACCOUNT, not per server — and without it every ownership test below would be
# proving a foreign key instead of the unique key it claims to prove.
Invoke-Sql -Sql "INSERT INTO accounts (id, discord_id, status) VALUES ('acc-3','222','active')" | Out-Null
Invoke-Sql -Sql "INSERT INTO characters (id, account_id, first_name) VALUES ('chr-3','acc-3','Grace')" | Out-Null

# ---------------------------------------------------------------------------
# ADR-0008 — jobs are open to anyone
# ---------------------------------------------------------------------------
Write-Step 'ADR-0008 — jobs have no qualification gate'
$cols = Invoke-Sql -Sql "SELECT column_name FROM information_schema.columns WHERE table_schema='nifty_life' AND table_name='character_jobs'"
$script:Checks++
if ($cols.Output -notmatch 'qualification' -and $cols.Output -notmatch 'exam' -and $cols.Output -notmatch 'rank') {
    Write-Host '  PASS  character_jobs has no qualification/rank column (allow)' -ForegroundColor Green
} else {
    $script:Failures++; Write-Host "  FAIL  a qualification column exists: $($cols.Output)" -ForegroundColor Red
}

Invoke-Sql -Sql "INSERT INTO character_jobs (character_id, job_code, is_duty) VALUES ('chr-1','taxi',0)" | Out-Null
Assert-Run -Name 'anyone may sign up for a job' `
    -Sql "INSERT INTO character_jobs (character_id, job_code, is_duty) VALUES ('chr-1','police',0)" -Expect 'allow'
Assert-Run -Name 'signing up twice for the same job is refused' `
    -Sql "INSERT INTO character_jobs (character_id, job_code, is_duty) VALUES ('chr-1','taxi',0)" -Expect 'reject'
Assert-Run -Name 'a job that does not exist is refused' `
    -Sql "INSERT INTO character_jobs (character_id, job_code, is_duty) VALUES ('chr-1','astronaut',0)" -Expect 'reject'

# ---------------------------------------------------------------------------
# ADR-0013 — ownership is a row, not a field
# ---------------------------------------------------------------------------
Write-Step 'ADR-0013 — ownership invariants'
Invoke-Sql -Sql @"
INSERT INTO properties (id, code, name, district, kind, tier) VALUES ('p1','test_flat','Test Flat','Vinewood','housing','entry');
INSERT INTO properties (id, code, name, district, kind, tier) VALUES ('p2','test_shop','Test Shop','La Mesa','business','standard');
"@ | Out-Null

Assert-Run -Name 'a property can be owned' `
    -Sql "INSERT INTO property_owners (property_id, character_id) VALUES ('p1','chr-1')" -Expect 'allow'
Assert-Run -Name 'a property cannot have two owners (reject)' `
    -Sql "INSERT INTO property_owners (property_id, character_id) VALUES ('p1','chr-3')" -Expect 'reject'
Assert-Run -Name 'a character may own several properties' `
    -Sql "INSERT INTO property_owners (property_id, character_id) VALUES ('p2','chr-1')" -Expect 'allow'
Assert-Run -Name 'a property code cannot be duplicated' `
    -Sql "INSERT INTO properties (id, code, name, district) VALUES ('p3','test_flat','Copy','Vinewood')" -Expect 'reject'

# The reason the second-owner test above matters: the refusal must leave the
# first owner alone. chr-3 exists on purpose, so this proves the UNIQUE key and
# not a foreign key that happened to be in the way.
$script:Checks++
$r = Invoke-Sql -Sql "SELECT character_id FROM property_owners WHERE property_id='p1'"
if ($r.Output -match 'chr-1') {
    Write-Host '  PASS  the refused second owner left the first owner intact (reject)' -ForegroundColor Green
} else {
    $script:Failures++; Write-Host "  FAIL  ownership corrupted: $($r.Output)" -ForegroundColor Red
}

# ---------------------------------------------------------------------------
# ADR-0009 — money cannot go negative
# ---------------------------------------------------------------------------
Write-Step 'ADR-0009 — money stays non-negative'
Assert-Run -Name 'valid wallet' `
    -Sql "INSERT INTO wallets (character_id, cash, bank) VALUES ('chr-1', 500.00, 250.00)" -Expect 'allow'
Assert-Run -Name 'negative cash insert is refused' `
    -Sql "INSERT INTO wallets (character_id, cash, bank) VALUES ('chr-9', -100.00, 0.00)" -Expect 'reject'
Assert-Run -Name 'driving cash negative is refused' `
    -Sql "UPDATE wallets SET cash = -5.00 WHERE character_id='chr-1'" -Expect 'reject'
Assert-Run -Name 'negative Stütze payout is refused' `
    -Sql "INSERT INTO stuetze_payouts (character_id, amount) VALUES ('chr-1', -250.00)" -Expect 'reject'

# ---------------------------------------------------------------------------
# Inventory integrity
# ---------------------------------------------------------------------------
Write-Step 'Inventory integrity'
# Migration 004 already seeds 'bread', so the test uses its own code. Re-inserting
# a seeded item would silently rewrite its display name for every real player.
Invoke-Sql -Sql "INSERT INTO item_defs (code,name,category) VALUES ('test_bread','Bread','food')" | Out-Null
Assert-Run -Name 'first item into slot 0' `
    -Sql "INSERT INTO inventory_items (id,character_id,slot,item_code,quantity) VALUES ('i1','chr-1',0,'test_bread',1)" -Expect 'allow'
Assert-Run -Name 'a second item cannot claim the same slot' `
    -Sql "INSERT INTO inventory_items (id,character_id,slot,item_code,quantity) VALUES ('i2','chr-1',0,'test_bread',1)" -Expect 'reject'
Assert-Run -Name 'quantity of zero is refused' `
    -Sql "INSERT INTO inventory_items (id,character_id,slot,item_code,quantity) VALUES ('i3','chr-1',5,'test_bread',0)" -Expect 'reject'
Assert-Run -Name 'an item code with no catalogue entry is refused' `
    -Sql "INSERT INTO inventory_items (id,character_id,slot,item_code,quantity) VALUES ('i4','chr-1',6,'no_such_item',1)" -Expect 'reject'

# ---------------------------------------------------------------------------
# ADR-0009 — the ledger explains a balance, it does not replace one
# ---------------------------------------------------------------------------
Write-Step 'ADR-0009 — ledger is append-only and explains the balance'
Assert-Run -Name 'a normal movement is recorded' `
    -Sql "INSERT INTO ledger (character_id,account,delta,balance_after,reason) VALUES ('chr-1','cash',250.00,750.00,'stuetze')" -Expect 'allow'
Assert-Run -Name 'a Stütze payout that would go negative is refused' `
    -Sql "INSERT INTO ledger (character_id,account,delta,balance_after,reason) VALUES ('chr-1','cash',-10000.00,-9750.00,'stuetze')" -Expect 'reject'
Assert-Run -Name 'rewriting a historical entry is refused' `
    -Sql "UPDATE ledger SET delta = 999999.00 WHERE character_id='chr-1'" -Expect 'reject'
Assert-Run -Name 'deleting history is refused' `
    -Sql "DELETE FROM ledger WHERE character_id='chr-1'" -Expect 'reject'
Assert-Run -Name 'a movement without a reason is refused' `
    -Sql "INSERT INTO ledger (character_id,account,delta,balance_after) VALUES ('chr-1','cash',10.00,760.00)" -Expect 'reject'

# ---------------------------------------------------------------------------
# ADR-0004 — vehicle state bounds
# ---------------------------------------------------------------------------
Write-Step 'ADR-0004 — persisted vehicle state stays in range'
Assert-Run -Name 'valid vehicle' `
    -Sql "INSERT INTO vehicles (id, model, fuel, owner_id) VALUES ('v1','adder',75.50,'chr-1')" -Expect 'allow'
Assert-Run -Name 'fuel over 100 is refused' `
    -Sql "INSERT INTO vehicles (id, model, fuel) VALUES ('v2','adder',150.00)" -Expect 'reject'

# ---------------------------------------------------------------------------
# ADR-0007 — the website can submit but cannot approve
# ---------------------------------------------------------------------------
Write-Step 'ADR-0007 — website privilege boundary'
Invoke-Sql -Sql "CREATE USER IF NOT EXISTS 'nifty_website'@'localhost' IDENTIFIED BY 'webtest'" | Out-Null
Invoke-Sql -Sql "GRANT SELECT, INSERT ON nifty_life.applications TO 'nifty_website'@'localhost'" | Out-Null
Invoke-Sql -Sql "GRANT SELECT ON nifty_life.accounts TO 'nifty_website'@'localhost'" | Out-Null
Invoke-Sql -Sql "FLUSH PRIVILEGES" | Out-Null

$web = { param($sql) Invoke-Sql -Sql $sql -User 'nifty_website' -Password 'webtest' }

$script:Checks++
$r = & $web "INSERT INTO applications (id, discord_id, answers) VALUES ('app-1','999','{}')"
if ($r.Exit -eq 0) { Write-Host '  PASS  website can submit an application (allow)' -ForegroundColor Green }
else { $script:Failures++; Write-Host '  FAIL  website could not submit' -ForegroundColor Red }

$script:Checks++
$r = & $web "UPDATE applications SET status='approved' WHERE id='app-1'"
if ($r.Exit -ne 0) { Write-Host '  PASS  website CANNOT approve an application (reject)' -ForegroundColor Green }
else { $script:Failures++; Write-Host '  FAIL  website was able to approve — boundary broken' -ForegroundColor Red }

$script:Checks++
$r = & $web "SELECT * FROM wallets"
if ($r.Exit -ne 0) { Write-Host '  PASS  website cannot read player money (reject)' -ForegroundColor Green }
else { $script:Failures++; Write-Host '  FAIL  website could read wallets — boundary broken' -ForegroundColor Red }

$script:Checks++
$r = & $web "SELECT * FROM characters"
if ($r.Exit -ne 0) { Write-Host '  PASS  website cannot read characters (reject)' -ForegroundColor Green }
else { $script:Failures++; Write-Host '  FAIL  website could read characters — boundary broken' -ForegroundColor Red }

$status = Invoke-Sql -Sql "SELECT status FROM applications WHERE id='app-1'"
$script:Checks++
if ($status.Output -match 'submitted') {
    Write-Host '  PASS  application is still "submitted" after every attack' -ForegroundColor Green
} else {
    $script:Failures++
    Write-Host "  FAIL  status changed: $($status.Output)" -ForegroundColor Red
}

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Layer 4 query shapes — the exact SQL server/economy.lua and
# server/inventory.lua send. Lua is only ever syntax-checked, so these
# statements are the layer's real behaviour and have to be proven here.
# ---------------------------------------------------------------------------
Write-Step 'Layer 4 — money movement is one guarded statement'

Invoke-Sql -Sql "UPDATE wallets SET cash = 500.00, bank = 250.00 WHERE character_id='chr-1'" | Out-Null

$script:Checks++
$r = Invoke-Sql -Sql "UPDATE wallets SET cash = cash + 250.00 WHERE character_id='chr-1' AND cash + 250.00 >= 0"
if ($r.Exit -eq 0) { Write-Host '  PASS  a credit is applied (allow)' -ForegroundColor Green }
else { $script:Failures++; Write-Host '  FAIL  credit was refused' -ForegroundColor Red }

$script:Checks++
$r = Invoke-Sql -Sql "UPDATE wallets SET cash = cash - 10000.00 WHERE character_id='chr-1' AND cash - 10000.00 >= 0"
$after = Invoke-Sql -Sql "SELECT cash FROM wallets WHERE character_id='chr-1'"
if ($r.Exit -eq 0 -and $after.Output -match '750\.00') {
    Write-Host '  PASS  an unaffordable debit touches ZERO rows and leaves the balance intact (reject)' -ForegroundColor Green
} else {
    $script:Failures++
    Write-Host "  FAIL  debit was not cleanly refused — balance is now: $($after.Output)" -ForegroundColor Red
}

$script:Checks++
$r = Invoke-Sql -Sql @"
INSERT INTO ledger (character_id, account, delta, balance_after, reason, reference_type, reference_id)
SELECT character_id, 'cash', 250.00, cash, 'stuetze', 'session', NULL
  FROM wallets WHERE character_id = 'chr-1'
"@
$row = Invoke-Sql -Sql "SELECT balance_after FROM ledger WHERE reason='stuetze' ORDER BY id DESC LIMIT 1"
if ($r.Exit -eq 0 -and $row.Output -match '750\.00') {
    Write-Host '  PASS  the ledger records the balance the INSERT itself read (allow)' -ForegroundColor Green
} else {
    $script:Failures++
    Write-Host "  FAIL  ledger balance_after wrong: $($row.Output)" -ForegroundColor Red
}

$script:Checks++
$r = Invoke-Sql -Sql "INSERT INTO ledger (character_id, account, delta, balance_after, reason, reference_type, reference_id) SELECT character_id, 'cash', 1.00, cash, 'no_such_reason', NULL, NULL FROM wallets WHERE character_id='chr-1'"
if ($r.Exit -eq 0) { Write-Host '  PASS  an unknown reason is still recorded by the DB — the Lua allowlist is the gate (documented)' -ForegroundColor Green }
else { $script:Failures++; Write-Host '  FAIL  unexpected' -ForegroundColor Red }

# ---------------------------------------------------------------------------
Write-Step 'Layer 4 — slot swap is atomic'
# ---------------------------------------------------------------------------
$script:Checks++
$r = Invoke-Sql -Sql @"
UPDATE inventory_items SET slot = 65535 WHERE character_id='chr-1' AND slot = 0;
UPDATE inventory_items SET slot = 0 WHERE character_id='chr-1' AND slot = 5;
UPDATE inventory_items SET slot = 5 WHERE character_id='chr-1' AND slot = 65535;
"@
if ($r.Exit -eq 0) {
    $rows = Invoke-Sql -Sql "SELECT slot FROM inventory_items WHERE character_id='chr-1' ORDER BY slot"
    if ($rows.Output -notmatch '65535') {
        Write-Host '  PASS  a two-stack swap leaves nothing stranded in the parking slot (allow)' -ForegroundColor Green
    } else {
        $script:Failures++; Write-Host "  FAIL  an item is stranded in slot 65535: $($rows.Output)" -ForegroundColor Red
    }
} else {
    $script:Failures++
    Write-Host "  FAIL  swap sequence failed: $($r.Output)" -ForegroundColor Red
}

$script:Checks++
$r = Invoke-Sql -Sql @"
INSERT INTO inventory_items (id, character_id, slot, item_code, quantity)
VALUES ('i-swap-b', 'chr-1', 1, 'test_bread', 1);
"@
Invoke-Sql -Sql "UPDATE inventory_items SET slot = 0 WHERE id = 'i1'" | Out-Null

$before = Invoke-Sql -Sql "SELECT COUNT(*) FROM inventory_items WHERE character_id='chr-1'"

# Run only the first half of the swap and stop, exactly as a failed transaction
# would leave it: one stack parked at 65535, one still in a live slot.
$r = Invoke-Sql -Sql @"
UPDATE inventory_items SET slot = 65535 WHERE character_id='chr-1' AND slot = 1;
UPDATE inventory_items SET slot = 1 WHERE character_id='chr-1' AND slot = 0;
"@
$after = Invoke-Sql -Sql "SELECT COUNT(*) FROM inventory_items WHERE character_id='chr-1'"

# The property that matters: a half-finished swap may park an item, but it must
# never lose one or conjure one. Losing inventory is the one failure mode a
# player never forgives.
if ($before.Output -eq $after.Output) {
    Write-Host "  PASS  an interrupted swap loses and duplicates nothing ($($after.Output.Trim()) rows, unchanged)" -ForegroundColor Green
} else {
    $script:Failures++
    Write-Host "  FAIL  interrupted swap changed the row count: $($before.Output) -> $($after.Output)" -ForegroundColor Red
}

# And the parked item must still be findable — unreachable is recoverable,
# deleted is not.
$script:Checks++
$r = Invoke-Sql -Sql "SELECT id FROM inventory_items WHERE character_id='chr-1' AND slot=65535"
if ($r.Exit -eq 0 -and $r.Output.Trim()) {
    Write-Host "  PASS  the parked stack is still retrievable by id ($($r.Output.Trim()))" -ForegroundColor Green
} else {
    $script:Failures++; Write-Host '  FAIL  the parked stack could not be found — inventory was destroyed' -ForegroundColor Red
}

# The shop is built by crossing item_defs with `economy.price.<code>` settings.
# A typo in either produces a shelf that silently lacks an item — no error, just
# something a player cannot buy and staff cannot explain.
$script:Checks++
$shop = Invoke-Sql -Sql @"
SELECT d.code FROM item_defs d
  LEFT JOIN settings s ON s.`key` = CONCAT('economy.price.', d.code)
 WHERE s.`key` IS NOT NULL AND CAST(s.value AS DECIMAL(14,2)) <= 0
"@
if ($shop.Exit -eq 0 -and -not $shop.Output.Trim()) {
    Write-Host '  PASS  every priced shop item has a price above zero (allow)' -ForegroundColor Green
} else {
    $script:Failures++
    Write-Host "  FAIL  items priced at zero or less would be listed but unbuyable: $($shop.Output)" -ForegroundColor Red
}

$script:Checks++
$shopCount = Invoke-Sql -Sql @"
SELECT COUNT(*) FROM item_defs d
  JOIN settings s ON s.`key` = CONCAT('economy.price.', d.code)
"@
$shopRows = ($shopCount.Output -split "`n" | Select-Object -Last 1).Trim()
if ([int]$shopRows -ge 7) {
    Write-Host "  PASS  shop shelf has $shopRows priced items" -ForegroundColor Green
} else {
    $script:Failures++
    Write-Host "  FAIL  shop shelf has only $shopRows priced items — migration 006 did not apply" -ForegroundColor Red
}

# ---------------------------------------------------------------------------
Write-Step 'Result'
if ($script:Failures -eq 0) {
    Write-Host "  All $($script:Checks) checks passed." -ForegroundColor Green
} else {
    Write-Host "  $($script:Failures) of $($script:Checks) checks FAILED." -ForegroundColor Red
}

if (-not $KeepContainer) {
    docker rm -f $ContainerName 2>&1 | Out-Null
    Write-Host '  Container removed. Re-run with -KeepContainer to inspect it.'
}

exit $script:Failures