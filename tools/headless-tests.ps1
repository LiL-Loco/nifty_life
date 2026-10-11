<#
.SYNOPSIS
    Executes the real server-side Lua modules against a real MariaDB.

.DESCRIPTION
    `tools/lua-lint.ps1` proves the files parse and `database/verify.ps1` proves
    the SCHEMA holds. Neither ever ran Economy.apply, Shop.buy or Jobs.endDuty.
    This does: it loads the project's own server modules with the small slice of
    the FiveM API they use stubbed out, and executes them against a throwaway
    database.

    What this does NOT cover, and why:
      * The DB transport is a `mariadb` CLI shim, not oxmysql. The SQL is real.
      * Appearance needs the collection natives, which no harness can provide.
      * Natives, NUI and net events remain unverified.

.EXAMPLE
    pwsh -File tools\headless-tests.ps1
    pwsh -File tools\headless-tests.ps1 -KeepContainer   # inspect afterwards
#>

[CmdletBinding()]
param(
    [string]$ContainerName = 'nifty-headless',
    [string]$Image = 'mariadb:11',
    [switch]$KeepContainer
)

$ErrorActionPreference = 'Continue'

Write-Host 'Starting throwaway MariaDB...' -ForegroundColor Cyan

# The user migration 016 grants to must EXIST before the migrations run.
#
# Migration 016 ends with
#     GRANT EXECUTE ON PROCEDURE nifty_life.confirm_portal_email TO 'nifty_website'@'localhost';
# and MariaDB aborts the whole init script on an unknown grantee (ERROR 1133, "Can't
# find any matching row in the user table"). The real server has that user; this
# throwaway container has only root. So migrations 017-019 never ran, the table count
# never reached the expected 27, and the harness failed at "migrations never
# completed" — which reads like broken SQL and is really a missing account.
#
# The user is created HERE, in the harness, and NOT in a migration. Putting
# `CREATE USER IF NOT EXISTS 'nifty_website' IDENTIFIED BY '...'` into the migration
# folder would mean committing a known password for a real account, and on the
# production MariaDB it would silently create that account with it if it were ever
# missing. A test fixture belongs to the test.
#
# The migrations are COPIED next to the fixture and that copy is what gets mounted.
# The alternative — overriding `--entrypoint` to copy the fixture in first — does not
# work: mariadb:11's entrypoint is a shell script, and replacing it with another
# command means the database never initialises at all ("container did not start").
$fixtureDir = Join-Path ([System.IO.Path]::GetTempPath()) 'nifty-headless-fixture'
if (Test-Path -LiteralPath $fixtureDir) { Get-ChildItem -LiteralPath $fixtureDir -File | ForEach-Object { rm -- $_.FullName } }
New-Item -ItemType Directory -Force -Path $fixtureDir | Out-Null

@'
-- Harness fixture, NOT a project migration. See tools/headless-tests.ps1.
CREATE USER IF NOT EXISTS 'nifty_website'@'localhost' IDENTIFIED BY 'fixture-only';
'@ | Set-Content -LiteralPath (Join-Path $fixtureDir '000_fixture_users.sql') -Encoding utf8

Copy-Item -Path "${PWD}/database/migrations/*.sql" -Destination $fixtureDir

docker rm -f $ContainerName 2>&1 | Out-Null
docker run --name $ContainerName `
    -e MARIADB_ROOT_PASSWORD=test `
    -e MARIADB_DATABASE=nifty_life `
    -v "${fixtureDir}:/docker-entrypoint-initdb.d:ro" `
    -d $Image 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host '  FAIL  container did not start' -ForegroundColor Red
    exit 1
}

# Same lesson as verify.ps1: the entrypoint runs init scripts against a TEMPORARY
# server, so readiness must be the expected table count, not `SELECT 1`.
#
# 31, not the 27 this used to assert. Migrations 016-019 added `portal_users`,
# `portal_email_tokens`, the confirmation routine and the chat settings, and the
# number was never updated — so the harness sat in its readiness loop for five
# minutes and then reported "migrations never completed", which reads like broken
# SQL while the migrations had in fact all succeeded.
#
# The actual count is printed on failure, because a stale constant that only says
# "never completed" is exactly the failure mode this check was written to prevent.
$expectedTables = 31
$ready = $false
$lastSeen = '0'
for ($i = 0; $i -lt 100; $i++) {
    Start-Sleep -Seconds 3
    $probe = docker exec $ContainerName mariadb -uroot -ptest nifty_life -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='nifty_life';" 2>&1
    $value = ($probe -join "`n").Trim()
    if ($LASTEXITCODE -eq 0 -and $value -match "\n(\d+)$") {
        $lastSeen = $Matches[1]
        if ($lastSeen -eq "$expectedTables") {
            $ready = $true
            break
        }
    }
}

if (-not $ready) {
    Write-Host "  FAIL  migrations never completed ($expectedTables tables expected, $lastSeen present)" -ForegroundColor Red
    docker logs $ContainerName 2>&1 | Select-String -Pattern 'ERROR' | Select-Object -Last 10
    exit 1
}
Write-Host "  PASS  schema ready ($expectedTables tables)" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Run the harness inside the database container, which already has both MariaDB
# and — after the lint toolchain is built — Lua 5.4. Mounting the repo read/write
# is required: the harness mutates settings rows to force a delivery failure.
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host 'Building Lua 5.4 toolchain...' -ForegroundColor Cyan

# Built from a FILE, not piped through stdin. A stdin Dockerfile gets a fresh
# cache key every run, so the layer cache never hits and every invocation leaves
# its layers behind — 20 GB of build cache before it was caught, at which point
# the Docker VM ran out of room and every migration failed with
# `ERROR 121 - Duplicate key on write or update`. That error reads like broken
# SQL and is really a full disk.
docker build -q -t nifty-lua54 -f tools/Dockerfile.lua54 . 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host '  FAIL  could not build the toolchain image' -ForegroundColor Red
    exit 1
}

Write-Host 'Executing server modules headlessly...' -ForegroundColor Cyan
Write-Host ''

# The toolchain image has the mariadb CLIENT but no server socket to the sibling
# container, so it talks over TCP. The harness reads these as env vars.
$output = docker run --rm `
    --network "container:$ContainerName" `
    -e NIFTY_DB_USER=root `
    -e NIFTY_DB_PASS=test `
    -e NIFTY_DB_NAME=nifty_life `
    -e NIFTY_ROOT=/work `
    -v "${PWD}:/work" `
    -w /work `
    --entrypoint lua5.4 `
    nifty-lua54 tools/headless-tests.lua 2>&1

$output | ForEach-Object {
    if ($_ -match '^\s*PASS') { Write-Host $_ -ForegroundColor Green }
    elseif ($_ -match '^\s*FAIL') { Write-Host $_ -ForegroundColor Red }
    elseif ($_ -match '^\s*-') { Write-Host $_ -ForegroundColor Red }
    elseif ($_ -match '^===') { Write-Host $_ -ForegroundColor Cyan }
    else { Write-Host $_ -ForegroundColor DarkGray }
}

$exitCode = $LASTEXITCODE

if (-not $KeepContainer) {
    docker rm -f $ContainerName 2>&1 | Out-Null
}

exit $exitCode