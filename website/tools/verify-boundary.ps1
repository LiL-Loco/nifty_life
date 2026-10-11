# verify-boundary.ps1 - assert what each database account can and cannot do.
#
# ADR-0007 claims the website can submit an application and never approve one.
# ADR-0022 claims the website can publish a post and never confirm its own
# identity binding. Both claims are enforced by GRANTS, not by code, which means
# they can be revoked by accident - a `GRANT ALL` during debugging, a
# `FLUSH PRIVILEGES` after a restore, a mysqldump replay.
#
# There are now THREE accounts (database/grants.sql):
#
#   nifty       the game server, full rights on the schema
#   nifty_website  the public site - read and submit, never decide
#   nifty_admin    the /admin routes - may decide, must not act as a player
#
# A boundary that is too tight is just as broken as one that is too loose, so
# every account is checked against BOTH its must-refuse list and its
# must-still-work list.
#
# CREDENTIAL PARSING. The credentials file is INI with one section per account.
# Reading it as a flat key=value dictionary silently picks the LAST `user=` and
# the LAST `password=`, so once the `[admin]` section was added this script began
# testing nifty_admin against nifty_website's expectations - and reported four
# failures that were really one bug in the harness. Sections are parsed
# explicitly below, and the account under test is printed in the header so a
# misparse is visible instead of quietly inverting the verdict.
#
# Usage:
#   pwsh -File website/tools/verify-boundary.ps1
#   pwsh -File website/tools/verify-boundary.ps1 -Section admin

param(
  [string]$CredentialsFile = (Join-Path $PSScriptRoot '..\..\database\.credentials.local'),
  [string]$Section = 'website',
  [string]$ClientExe = ''
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Credentials, parsed PER SECTION. Read from the git-ignored local file, never
# hardcoded here.
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $CredentialsFile)) {
  throw "Credentials file not found: $CredentialsFile"
}

$sections = @{}
$current = $null
foreach ($line in Get-Content -LiteralPath $CredentialsFile) {
  if ($line -match '^\s*\[(.+)\]\s*$') {
    $current = $Matches[1].Trim()
    if (-not $sections.ContainsKey($current)) { $sections[$current] = @{} }
    continue
  }
  if ($null -eq $current) { continue }
  if ($line -match '^\s*([^#;=\[][^=]*)=(.*)$') {
    $sections[$current][$Matches[1].Trim()] = $Matches[2].Trim()
  }
}

if (-not $sections.ContainsKey($Section)) {
  throw "No [$Section] section in $CredentialsFile. Found: $($sections.Keys -join ', ')"
}

$dbUser = $sections[$Section]['user']
$dbPass = $sections[$Section]['password']
$dbHost = if ($sections[$Section]['host']) { $sections[$Section]['host'] } else { 'localhost' }

if (-not $dbUser -or -not $dbPass) {
  throw "Could not read user/password from the [$Section] section of $CredentialsFile"
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
# The expectations, per account. Keep in sync with database/grants.sql.
# ---------------------------------------------------------------------------

# What the PUBLIC site must never be able to do.
$websiteDenied = @(
  @{ name = 'approve an application';        sql = "UPDATE applications SET status='approved' WHERE discord_id='nobody'" },
  @{ name = 'rewrite the submitted answers';  sql = "UPDATE applications SET answers='{}' WHERE discord_id='nobody'" },
  @{ name = 'confirm its own pairing request'; sql = "UPDATE web_link_requests SET code=code WHERE discord_id='nobody'" },
  @{ name = 'write a character link directly'; sql = "INSERT INTO web_links (discord_id, character_id) VALUES ('nobody', UUID())" },
  @{ name = 'read the pairing codes';          sql = 'SELECT * FROM web_pairing_codes' },
  @{ name = 'read wallets';                    sql = 'SELECT * FROM wallets' },
  @{ name = 'delete a post';                   sql = "DELETE FROM peeper_posts WHERE id='nobody'" },
  @{ name = 'soft-delete a post';              sql = "UPDATE peeper_posts SET deleted_at=NOW() WHERE id='nobody'" },
  @{ name = 'rewrite a post body';             sql = "UPDATE peeper_posts SET body='x' WHERE id='nobody'" },
  @{ name = 'resolve a report';                sql = "UPDATE peeper_reports SET status='dismissed' WHERE id='nobody'" },
  @{ name = 'remove another like';             sql = "DELETE FROM peeper_likes WHERE character_id<>'nobody'" },
  # A destructive boundary check is a boundary check that destroys the thing it
  # protects. The id below matches no real row on purpose: the column grant is
  # verified before any row is matched, and a post a moderator actually removed
  # stays removed.
  @{ name = 'soft-delete a post';              sql = "UPDATE peeper_posts SET deleted_at=NOW() WHERE id='00000000-0000-0000-0000-000000000000'" },
  # Migration 012 let a post be authored by a Discord account as well as by a
  # character, and the public pool holds INSERT on this table. Migration 014
  # column-scopes that grant so `author_discord_id` is NOT grantable here — this
  # statement must therefore fail, or a website compromise could forge posts as
  # the owner.
  @{ name = 'post as a Discord identity';      sql = "INSERT INTO peeper_posts (id, author_character, author_discord_id, author_name, body) VALUES (UUID(), NULL, '1', 'x', 'y')" },
  @{ name = 'like as a Discord identity';      sql = "INSERT INTO peeper_likes (post_id, character_id, author_discord_id) VALUES ('x', NULL, '1')" },
  @{ name = 'delete an application';           sql = "DELETE FROM applications WHERE discord_id='nobody'" },
  # The staff mirror. BOTH web accounts hold SELECT only — the bot in `bot/` is
  # the sole writer, using the GAME account. If any of these three ever pass, a
  # website account can appoint itself moderator, and the Discord role stops
  # being the source of truth.
  @{ name = 'appoint themselves staff';        sql = "INSERT INTO staff (discord_id, role_id) VALUES ('nobody','1')" },
  @{ name = 'promote a staff row';             sql = "UPDATE staff SET role_id='1' WHERE discord_id='nobody'" },
  @{ name = 'demote a moderator';              sql = "DELETE FROM staff WHERE discord_id='nobody'" }
)

$websiteAllowed = @(
  @{ name = 'read the feed';          sql = "SELECT id FROM peeper_posts WHERE deleted_at IS NULL LIMIT 1" },
  @{ name = 'read own application';   sql = "SELECT id FROM applications WHERE discord_id='nobody' LIMIT 1" },
  @{ name = 'read own link';          sql = "SELECT character_id FROM web_links WHERE discord_id='nobody' LIMIT 1" },
  @{ name = 'read the staff mirror';  sql = 'SELECT discord_id FROM staff LIMIT 1' }
)

# What the ADMIN pool may do, and what it still may not do.
# Admin decides applications. Admin does NOT act as a player: it cannot write a
# pairing request, cannot insert a character link, cannot touch wallets, cannot
# moderate the feed. Moderation stays where ADR-0022 put it.
$adminDenied = @(
  @{ name = 'write a character link directly'; sql = "INSERT INTO web_links (discord_id, character_id) VALUES ('nobody', UUID())" },
  @{ name = 'write a pairing request';         sql = "INSERT INTO web_link_requests (discord_id, code) VALUES ('nobody','abcd')" },
  @{ name = 'read the pairing codes';          sql = 'SELECT * FROM web_pairing_codes' },
  @{ name = 'read wallets';                    sql = 'SELECT * FROM wallets' },
  @{ name = 'delete a post';                   sql = "DELETE FROM peeper_posts WHERE id='nobody'" },
  @{ name = 'rewrite a post body';             sql = "UPDATE peeper_posts SET body='x' WHERE id='nobody'" },
  @{ name = 'resolve a report';                sql = "UPDATE peeper_reports SET status='dismissed' WHERE id='nobody'" },
  @{ name = 'rewrite the submitted answers';   sql = "UPDATE applications SET answers='{}' WHERE discord_id='nobody'" },
  @{ name = 'delete an application';           sql = "DELETE FROM applications WHERE discord_id='nobody'" },
  # The admin pool cannot READ the feed or the character links. That looks like an
  # oversight and is not: the admin routes resolve those through the PUBLIC pool on
  # purpose, because deciding whether to trust the privileged connection must not
  # itself require the privileged connection. Feed moderation stays in game (ADR-0022).
  @{ name = 'read own link';                   sql = "SELECT character_id FROM web_links WHERE discord_id='nobody' LIMIT 1" },
  # Admin decides applications. It does NOT appoint staff: `isStaff()` runs on
  # the public pool and reads a mirror only the bot can write.
  @{ name = 'appoint themselves staff';        sql = "INSERT INTO staff (discord_id, role_id) VALUES ('nobody','1')" },
  @{ name = 'promote a staff row';             sql = "UPDATE staff SET role_id='1' WHERE discord_id='nobody'" },
  @{ name = 'demote a moderator';              sql = "DELETE FROM staff WHERE discord_id='nobody'" },
  # Still no physical delete for ANY account. A removed post stays in the table as
  # evidence; only `deleted_at` is written.
  @{ name = 'erase a post for good';           sql = "DELETE FROM peeper_posts WHERE id='nobody'" }
)

$adminAllowed = @(
  @{ name = 'read characters';            sql = 'SELECT id, is_staff FROM characters LIMIT 1' },
  @{ name = 'read accounts';              sql = 'SELECT id, status FROM accounts LIMIT 1' },
  @{ name = 'read bans';                  sql = 'SELECT id, discord_id FROM bans LIMIT 1' },
  @{ name = 'read the staff mirror';      sql = 'SELECT discord_id FROM staff LIMIT 1' },
  @{ name = 'approve an application';     sql = "UPDATE applications SET status='approved', reviewed_at=NOW(), reviewed_by_discord_id='1', decision_note=NULL WHERE discord_id='nobody'" },
  # The team writes on P&R without a linked character. Inserting author_discord_id
  # is what makes a post attributable to the team instead of to nobody.
  #
  # EXPLAIN, not INSERT: MariaDB checks column privileges before it matches any
  # row, so EXPLAIN proves the grant and writes nothing. A real INSERT here would
  # leave a staff post in the live feed that the script has no privilege to
  # remove — the admin account has no DELETE on this table, which is the point.
  @{ name = 'insert a staff post';        sql = "EXPLAIN INSERT INTO peeper_posts (id, author_discord_id, author_name, body, source) VALUES (UUID(), '1', 'Team', 'Hinweis', 'staff')" },
  # Same reasoning: the column grant is what is under test, so the WHERE clause
  # deliberately matches nothing. A soft delete against real posts would be a
  # boundary test that destroys the thing it is protecting.
  @{ name = 'soft-delete a post';         sql = "UPDATE peeper_posts SET deleted_at=NOW(), deleted_by_discord_id='1', deleted_reason='probe' WHERE deleted_at IS NULL AND id = '00000000-0000-0000-0000-000000000000'" }
)

switch ($Section) {
  'website' { $denied = $websiteDenied; $allowed = $websiteAllowed }
  'admin'   { $denied = $adminDenied;   $allowed = $adminAllowed }
  default   { throw "No expectations defined for section '$Section'." }
}

$pass = 0
$fail = 0

Write-Host ''
Write-Host "Verifying the privilege boundary for '$dbUser'@$dbHost  [section: $Section]" -ForegroundColor Cyan
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