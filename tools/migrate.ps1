<#
.SYNOPSIS
    Applies every outstanding database migration to the server's own database.

.DESCRIPTION
    Migration 003 left a note that no runner existed yet and that
    `schema_migrations` was "the landing spot for a proper runner". This is
    that runner.

    Why it matters beyond tidiness: until now the ONLY way the schema was ever
    built was by starting a throwaway container whose entrypoint ran the files
    in alphabetical order. That has three consequences, all of which bit us:

      * No record of what was applied. "Is migration 007 in?" was answerable
        only by looking.
      * A failure halfway through left the database in a state nobody could
        describe, and re-running was the only available repair.
      * It could not target a database that already exists — which is what a
        developer's own local MariaDB is.

    The connection comes from `server.cfg`, the same file FXServer reads, so
    there is exactly one place where the credentials live and it is
    git-ignored. Nothing here writes a credential anywhere.

    Migrations are applied in filename order and only when absent from
    `schema_migrations`. All of them are written to be re-runnable (IF NOT
    EXISTS / ON DUPLICATE KEY), so a file that failed halfway is safe to apply
    again.

.PARAMETER Config
    Path to server.cfg. Read for the connection string only.

.PARAMETER List
    Show what would be applied and exit. Changes nothing.

.EXAMPLE
    pwsh -File tools\migrate.ps1
    pwsh -File tools\migrate.ps1 -List
#>

[CmdletBinding()]
param(
    [string]$Config = 'server.cfg',
    [switch]$List
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Locate the client.
#
# The MariaDB CLI is rarely on PATH on Windows even when the server is installed
# as a service, so Program Files is searched as well. `mariadb` is preferred
# over `mysql` only because that is what MariaDB ships under both names.
# ---------------------------------------------------------------------------
function Find-MariaDbClient {
    foreach ($name in @('mariadb', 'mysql')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }

    $roots = @("$env:ProgramFiles\MariaDB*", "${env:ProgramFiles(x86)}\MariaDB*")

    foreach ($pattern in $roots) {
        $dirs = Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending

        foreach ($dir in $dirs) {
            foreach ($exe in @('mariadb.exe', 'mysql.exe')) {
                $candidate = Join-Path $dir.FullName "bin\$exe"
                if (Test-Path -LiteralPath $candidate) { return $candidate }
            }
        }
    }

    return $null
}

$client = Find-MariaDbClient

if (-not $client) {
    Write-Host 'Could not find a MariaDB/MySQL client.' -ForegroundColor Red
    Write-Host 'Install MariaDB, or add its bin directory to PATH.' -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Read the connection string out of server.cfg.
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $Config)) {
    Write-Host "  FAIL  $Config not found. Copy server.cfg.example to server.cfg." -ForegroundColor Red
    exit 1
}

$configText = Get-Content -LiteralPath $Config -Raw
$match = [regex]::Match($configText, 'mysql_connection_string\s+"([^"]+)"')

if (-not $match.Success) {
    Write-Host '  FAIL  no mysql_connection_string in server.cfg' -ForegroundColor Red
    exit 1
}

$url = [uri]::UnescapeDataString($match.Groups[1].Value)
$parts = [regex]::Match($url, '^mysql://(?<user>[^:@/]+)(:(?<pass>[^@]*))?@(?<host>[^:/]+)(:(?<port>\d+))?/(?<db>[^?]+)')

if (-not $parts.Success) {
    Write-Host '  FAIL  could not parse the connection string' -ForegroundColor Red
    Write-Host '        expected: mysql://user:password@host:port/database' -ForegroundColor Red
    exit 1
}

$dbUser = $parts.Groups['user'].Value
$dbPass = $parts.Groups['pass'].Value
$dbHost = $parts.Groups['host'].Value
$dbPort = if ($parts.Groups['port'].Success) { $parts.Groups['port'].Value } else { '3306' }
$dbName = $parts.Groups['db'].Value

# The password goes through the environment, never `--password=` on the command
# line, where any process on the machine could read it out of the process list.
# MYSQL_PWD is the least-bad option available without writing a secrets file.
$env:MYSQL_PWD = $dbPass

# Connecting to a LOCAL server over TLS buys nothing and costs a warning line on
# every invocation ("ssl-verify-server-cert is disabled, because of an insecure
# passwordless login"). That warning arrives on stderr, which is captured
# alongside stdout — and it silently broke the "has this migration run?"
# comparison below, because the captured text was `WARNING: ...1` rather than
# `1`. The migration list came back empty and the runner re-applied everything.
$dbIsLocal = $dbHost -in @('127.0.0.1', 'localhost', '::1')

function Invoke-Sql {
    param([string]$Sql, [string]$Database)

    $arguments = @(
        "--user=$dbUser", "--host=$dbHost", "--port=$dbPort", '--protocol=TCP',
        '--default-character-set=utf8mb4', '--batch', '--skip-column-names'
    )
    if ($dbIsLocal) { $arguments += '--skip-ssl' }
    if ($Database) { $arguments += $Database }

    return & $client @arguments -e $Sql 2>&1
}

# The value of the LAST line that is not a driver notice.
#
# `mariadb` writes warnings to stderr and `2>&1` merges them into stdout, so a
# naive `($output -join '').Trim()` can return `WARNING: ...` followed by the
# real value. Anything parsed back out of SQL must go through this.
function Get-LastValue {
    param($Output)

    $values = @()
    foreach ($line in @($Output)) {
        $text = $line.ToString()
        if ($text -notmatch '^\s*WARNING' -and $text.Trim() -ne '') { $values += $text.Trim() }
    }

    if ($values.Count -eq 0) { return '' }
    return $values[-1]
}

try {
    Write-Host "Target: $dbUser@$dbHost`:$dbPort/$dbName" -ForegroundColor Cyan

    # --- reachability -------------------------------------------------------
    $ping = Invoke-Sql -Sql 'SELECT 1;'
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FAIL  cannot reach MariaDB at $dbHost`:$dbPort" -ForegroundColor Red
        Write-Host '        is the service running?' -ForegroundColor Red
        Write-Host ($ping -join "`n") -ForegroundColor DarkGray
        exit 1
    }

    # --- create the database if it is not there -----------------------------
    # `CREATE DATABASE IF NOT EXISTS` is the one statement safe to run before
    # the migrations, since 001 creates tables and cannot create its own schema.
    $create = Invoke-Sql -Sql "CREATE DATABASE IF NOT EXISTS ``$dbName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    if ($LASTEXITCODE -ne 0) {
        Write-Host '  FAIL  could not create the database' -ForegroundColor Red
        Write-Host ($create -join "`n") -ForegroundColor DarkGray
        exit 1
    }

    # --- what is already applied? ------------------------------------------
    # schema_migrations is created BY migration 001, so before the first run it
    # does not exist. An empty result is the correct answer in that case, not an
    # error to fail on.
    $applied = @()
    $existing = Invoke-Sql -Sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$dbName' AND table_name = 'schema_migrations';"

    if ($LASTEXITCODE -eq 0 -and (Get-LastValue $existing) -eq '1') {
        $applied = @(Invoke-Sql -Sql 'SELECT version FROM schema_migrations;' -Database $dbName |
            Where-Object { $_.ToString() -notmatch '^\s*WARNING' } |
            ForEach-Object { $_.ToString().Trim() })
    }

    Write-Host "  already applied: $($applied.Count)" -ForegroundColor DarkGray

    # --- outstanding --------------------------------------------------------
    $files = Get-ChildItem -LiteralPath "$PWD/database/migrations" -Filter '*.sql' -File |
        Sort-Object Name

    $pending = @($files | Where-Object { $applied -notcontains $_.Name })

    if ($pending.Count -eq 0) {
        Write-Host '  nothing to do — the database is up to date.' -ForegroundColor Green
        exit 0
    }

    if ($List) {
        Write-Host ''
        $pending | ForEach-Object { Write-Host "  would apply: $($_.Name)" -ForegroundColor Yellow }
        exit 0
    }

    # --- apply --------------------------------------------------------------
    Write-Host ''
    Write-Host "Applying $($pending.Count) migration(s)..." -ForegroundColor Cyan

    foreach ($file in $pending) {
        $sqlText = Get-Content -LiteralPath $file.FullName -Raw

        # A file goes in whole, through stdin. Piping it means no statement ever
        # passes through a shell quoting layer — the same reason the headless
        # harness writes to a temp file instead of using `-e`.
        $output = $sqlText | & $client `
            "--user=$dbUser" "--host=$dbHost" "--port=$dbPort" '--protocol=TCP' `
            '--default-character-set=utf8mb4' $dbName 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Host "  FAIL  $($file.Name)" -ForegroundColor Red
            Write-Host ($output -join "`n") -ForegroundColor DarkGray
            Write-Host ''
            Write-Host '  Not recorded in schema_migrations, so re-running this command' -ForegroundColor Yellow
            Write-Host '  will retry just this file. Every migration is written to be' -ForegroundColor Yellow
            Write-Host '  re-runnable, so a half-applied one is safe to apply again.' -ForegroundColor Yellow
            exit 1
        }

        $record = Invoke-Sql -Sql "INSERT INTO schema_migrations (version) VALUES ('$($file.Name)');" -Database $dbName
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  FAIL  applied $($file.Name) but could not record it" -ForegroundColor Red
            Write-Host ($record -join "`n") -ForegroundColor DarkGray
            exit 1
        }

        Write-Host "  OK    $($file.Name)" -ForegroundColor Green
    }

    # --- summary ------------------------------------------------------------
    $tables = Invoke-Sql -Sql "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$dbName';"
    $tableCount = if ($tables) { Get-LastValue $tables } else { '?' }
    if ($tableCount -eq '') { $tableCount = '?' }

    Write-Host ''
    Write-Host "  Done. $tableCount tables in $dbName." -ForegroundColor Green
}
finally {
    # Do not leave the password in this process's environment for whatever runs
    # next in the same session.
    Remove-Item Env:\MYSQL_PWD -ErrorAction SilentlyContinue
}