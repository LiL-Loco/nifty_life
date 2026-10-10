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
$expectedTables = 16
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
Invoke-Sql -Sql "INSERT INTO item_defs (code,name,category) VALUES ('bread','Bread','food')" | Out-Null
Assert-Run -Name 'first item into slot 0' `
    -Sql "INSERT INTO inventory_items (id,character_id,slot,item_code,quantity) VALUES ('i1','chr-1',0,'bread',1)" -Expect 'allow'
Assert-Run -Name 'a second item cannot claim the same slot' `
    -Sql "INSERT INTO inventory_items (id,character_id,slot,item_code,quantity) VALUES ('i2','chr-1',0,'bread',1)" -Expect 'reject'
Assert-Run -Name 'quantity of zero is refused' `
    -Sql "INSERT INTO inventory_items (id,character_id,slot,item_code,quantity) VALUES ('i3','chr-1',5,'bread',0)" -Expect 'reject'

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