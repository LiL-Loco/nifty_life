<#
.SYNOPSIS
    Syntax-checks every Lua file in resources/ with luac.

.DESCRIPTION
    FiveM runs Lua 5.4, so a file that parses under a different Lua version is
    not evidence of anything. This builds a tiny Lua 5.4 toolchain image (reusing
    the MariaDB base already required for database/verify.ps1, so no extra
    project dependency) and parses every file with luac -p.

    luac -p parses without executing, so nothing needs a running game server.

.EXAMPLE
    pwsh -File tools\lua-lint.ps1
#>

[CmdletBinding()]
param(
    [string]$ToolImage = 'nifty-lua54',
    # ONLY our own resources. This used to scan everything under `resources/`,
    # which worked until oxmysql, Bob74_IPL, mapmanager and spawnmanager were
    # downloaded — and then six of THEIR files failed to parse under plain
    # lua5.4, because they are written for FiveM's Lua, not Debian's.
    #
    # Linting another project's release tells us nothing about ours, and it
    # turns a green suite red for a reason nobody can act on. Same rule as
    # .gitignore: external dependencies are downloaded, not maintained.
    [string]$Path = 'resources/[nifty]',
    [switch]$All
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Toolchain image — see tools/Dockerfile.lua54 for why it is a file and not a
# here-string piped into `docker build -f -`.
# ---------------------------------------------------------------------------

Write-Host 'Ensuring Lua 5.4 toolchain image...' -ForegroundColor Cyan
# Built from tools/Dockerfile.lua54, not piped through stdin. A Dockerfile
# arriving on stdin gets a fresh cache key every run and leaves its layers
# behind — that accumulated 20 GB of build cache across this project's history.
docker build -q -t $ToolImage -f tools/Dockerfile.lua54 . 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host '  FAIL  could not build the toolchain image' -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------------------
# Parse every file. $Path arrives as $1 to the inner bash, so it is never
# interpolated into the script text.
# ---------------------------------------------------------------------------
$check = @'
fail=0
total=0
while IFS= read -r f; do
  total=$((total+1))
  if luac5.4 -p "$f" 2>/tmp/err; then
    echo "OK   ${f#/work/}"
  else
    fail=$((fail+1))
    echo "FAIL ${f#/work/}"
    sed 's/^/       /' /tmp/err
  fi
done < <(find "/work/$1" -name '*.lua' | sort)
echo "RESULT $fail $total"
'@

Write-Host ''

$scanPath = if ($All) { 'resources' } else { $Path }

if ($All) {
    Write-Host 'Parsing EVERY Lua file under resources/ — this includes third-party' -ForegroundColor Yellow
    Write-Host 'resources, which are written for FiveM''s Lua and may fail. Expect noise.' -ForegroundColor Yellow
} else {
    Write-Host "Parsing Lua files under $scanPath with luac 5.4..." -ForegroundColor Cyan
}

# The path reaches the inner bash as $1 and is quoted there, so the square
# brackets in `resources/[nifty]` stay literal. PowerShell's own `-Path` would
# treat them as a character class, which is why this is `$scanPath` and never
# `-Path`.
$result = $check | docker run --rm -i -v "${PWD}:/work" -w /work --entrypoint bash $ToolImage -s $scanPath 2>&1

$result | ForEach-Object {
    if ($_ -match '^OK ') { Write-Host "  $_" -ForegroundColor Green }
    elseif ($_ -match '^FAIL ') { Write-Host "  $_" -ForegroundColor Red }
    elseif ($_ -match '^       ') { Write-Host "  $_" -ForegroundColor DarkGray }
    elseif ($_ -match '^RESULT') { Write-Host ''; Write-Host "  $_" -ForegroundColor Cyan }
}

$line = $result | Where-Object { $_ -match '^RESULT' } | Select-Object -Last 1

if ($line -match '^RESULT (\d+) (\d+)') {
    $failCount = [int]$Matches[1]
    $totalCount = [int]$Matches[2]
    if ($failCount -eq 0) {
        Write-Host "  All $totalCount files parse under Lua 5.4." -ForegroundColor Green
        exit 0
    }
    Write-Host "  $failCount of $totalCount files failed to parse." -ForegroundColor Red
    exit $failCount
}

Write-Host '  FAIL  no result produced' -ForegroundColor Red
exit 1