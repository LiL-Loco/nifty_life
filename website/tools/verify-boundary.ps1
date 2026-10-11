# verify-boundary.ps1 — assert that the website database user is powerless.
#
# ADR-0007 claims the website can submit an application and never approve one.
# ADR-0022 claims the website can publish a post and never confirm its own
# identity binding. Both claims are enforced by GRANTS, not by code, which means
# they can be revoked by accident — a `GRANT ALL` during debugging, a
# `FLUSH PRIVILEGES` after a restore, a mysqldump replay.
#
# This runs as `nifty_website` and asserts every prohibited statement is
# refused. If a future change widens the grants, this goes red.
#
# Usage:  pwsh -File website/tools/verify-boundary.ps1

param(
  [string]$CredentialsFile = (Join-Path $PSScriptRoot '..\..\database\.credentials.local'),
  [string]$ClientExe = ''
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Credentials. Read from the git-ignored local file, never hardcoded here.
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $CredentialsFile)) {
  throw "Credentials file not found: $CredentialsFile"
}

$values = @{}
foreach ($line in Get-Content -LiteralPath $CredentialsFile) {
  if ($line -match '^\s*([^#\[][^=]*)=(.*)$') { $values[$matches[1].Trim()] = $matches[2].Trim() }
}

$dbUser = $values['user']
$dbPass = $values['password']
$dbHost = if ($values['host']) { $values['host'] } else { 'localhost' }

if (-not $dbUser -or -not $dbPass) {
  throw "Could not read user/password from $CredentialsFile"
}

# ---------------------------------------------------------------------------
# Locate the client. Rarely on PATH on Windows even when MariaDB is installed.
# ---------------------------------------------------------------------------
if (-not $ClientExe) {
  $found = Get-Command mariadb -ErrorAction SilentlyContinue
  if ($found) {
    $ClientExe = $found.Source
  } else {
    $root = Get-ChildItem -Path "$env:ProgramFiles\MariaDB*" -Directory -ErrorAction SilentlyContinue |
      Sort-Object Name -Descending | Select-Object -First 1
    if ($root) {
      $ClientExe = Join-Path $root.FullName 'bin\mariadb.exe'
    }
  }
}

if (-not $ClientExe -or -not (Test-Path -LiteralPath $ClientExe)) {
  throw 'mariadb client not found. Pass -ClientExe <path to mariadb.exe>.'
}

$env:MYSQL_PWD = $dbPass

function Invoke-Sql([string]$sql) {
  $output = & $ClientExe -h $dbHost -u $dbUser nifty_life --batch --skip-ssl -e $sql 2>&1
  return [pscustomobject]@{
    ExitCode = $LASTEXITCODE
    Output = ($output | Out-String)
  }
}

# ---------------------------------------------------------------------------
# The prohibited statements. Every one of these MUST be refused.
#
# This list is the ADR translated into something executable. Adding a line here
# costs nothing; removing one silently weakens the project, so keep it in sync
# with grants.sql.
# ---------------------------------------------------------------------------
$denied = @(
  @{ name = 'approve an application';        sql = "UPDATE applications SET status='approved' WHERE discord_id='nobody'" },
  @{ name = 'confirm its own pairing request'; sql = "UPDATE web_link_requests SET code=code WHERE discord_id='nobody'" },
  @{ name = 'write a character link directly'; sql = "INSERT INTO web_links (discord_id, character_id) VALUES ('nobody', UUID())" },
  @{ name = 'read the pairing codes';          sql = 'SELECT * FROM web_pairing_codes' },
  @{ name = 'read wallets';                    sql = 'SELECT * FROM wallets' },
  @{ name = 'read characters';                 sql = 'SELECT * FROM characters' },
  @{ name = 'delete a post';                   sql = "DELETE FROM peeper_posts WHERE id='nobody'" },
  @{ name = 'un-delete a post';                sql = "UPDATE peeper_posts SET deleted_at=NOW() WHERE id='nobody'" },
  @{ name = 'resolve a report';                sql = "UPDATE peeper_reports SET status='dismissed' WHERE id='nobody'" },
  @{ name = 'remove another like';             sql = "DELETE FROM peeper_likes WHERE character_id<>'nobody'" }
)

# ---------------------------------------------------------------------------
# And the statements that must keep working. A boundary that is too tight is
# still a broken website, so these are checked too.
# ---------------------------------------------------------------------------
$allowed = @(
  @{ name = 'read the feed';            sql = "SELECT id FROM peeper_posts WHERE deleted_at IS NULL LIMIT 1" },
  @{ name = 'read own application';     sql = "SELECT id FROM applications WHERE discord_id='nobody' LIMIT 1" },
  @{ name = 'read own link';            sql = "SELECT character_id FROM web_links WHERE discord_id='nobody' LIMIT 1" }
)

$pass = 0
$fail = 0

Write-Host ''
Write-Host "Verifying the privilege boundary for '$dbUser'@$dbHost" -ForegroundColor Cyan
Write-Host ''

foreach ($case in $denied) {
  $result = Invoke-Sql $case.sql

  if ($result.ExitCode -ne 0) {
    Write-Host ('  PASS  refused: ' + $case.name) -ForegroundColor Green
    $pass++
  } else {
    Write-Host ('  FAIL  ALLOWED: ' + $case.name) -ForegroundColor Red
    Write-Host ('        ' + $result.Output.Trim()) -ForegroundColor DarkRed
    $fail++
  }
}

foreach ($case in $allowed) {
  $result = Invoke-Sql $case.sql

  if ($result.ExitCode -eq 0) {
    Write-Host ('  PASS  permitted: ' + $case.name) -ForegroundColor Green
    $pass++
  } else {
    Write-Host ('  FAIL  REFUSED: ' + $case.name) -ForegroundColor Red
    Write-Host ('        ' + $result.Output.Trim()) -ForegroundColor DarkRed
    $fail++
  }
}

Write-Host ''
if ($fail -eq 0) {
  Write-Host "  $pass/$($pass + $fail) boundary checks passed." -ForegroundColor Green
  exit 0
} else {
  Write-Host "  $fail boundary check(s) FAILED." -ForegroundColor Red
  exit 1
}