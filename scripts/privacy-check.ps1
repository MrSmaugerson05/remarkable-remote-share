[CmdletBinding()]
param([ValidateSet('working', 'staged', 'history')][string]$Mode = 'working')

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mail = 'gma' + 'il[.]com'
$network = '[.]ts[.]net'
$address = '100[.][0-9]{1,3}[.][0-9]{1,3}[.][0-9]{1,3}'
$key = 'tskey' + '-'
$state = 'tailscaled' + '[.]state'
$private = 'BEGIN.*PRIVATE' + ' KEY'
$patterns = @("@$mail", '[A-Za-z]:[/\\]Users[/\\]', $network, $address, $key, $private, $state)
$localPatterns = if ($env:REMOTE_SHARE_PRIVATE_PATTERNS_FILE) {
    $env:REMOTE_SHARE_PRIVATE_PATTERNS_FILE
} else {
    Join-Path $Root '.privacy-local-patterns'
}

# Exact personal identifiers stay in an ignored local file. Historical public
# commits use generic rules; working and staged scans apply the local additions.
if ($Mode -ne 'history' -and (Test-Path -LiteralPath $localPatterns -PathType Leaf)) {
    $patterns += Get-Content -LiteralPath $localPatterns |
        Where-Object { $_ -notmatch '^\s*(#|$)' }
}
$forbidden = '(?:' + ($patterns -join '|') + ')'

Push-Location $Root
try {
    switch ($Mode) {
        'working' { $files = @(git ls-files --cached --others --exclude-standard | Sort-Object -Unique) }
        'staged'  { $files = @(git ls-files | Sort-Object -Unique) }
        'history' { $files = @(git log --all --format= --name-only | Where-Object { $_ } | Sort-Object -Unique) }
    }
    if ($LASTEXITCODE -ne 0) { throw 'Git file enumeration failed' }

    $allowed = @(Get-Content -LiteralPath '.public-files' | Sort-Object -Unique)
    if (Compare-Object -ReferenceObject $allowed -DifferenceObject $files) {
        throw "$Mode file list differs from .public-files"
    }

    if ($files | Where-Object { $_ -match '\.(o|so|a|exe|zip|tgz|tar|gz)$|(^|/)(build|dist|state|run|evidence|research)/|hashtab' }) {
        throw 'Generated, private, or binary material is present'
    }

    if ($Mode -eq 'history') {
        $commits = @(git rev-list --all)
        if ($commits.Count -gt 0) {
            $matches = git grep -IEn $forbidden @commits
            if ($LASTEXITCODE -eq 0) { throw "Privacy pattern found in history:`n$matches" }
            if ($LASTEXITCODE -gt 1) { throw 'Git history scan failed' }
        }
    } else {
        foreach ($file in $files) {
            $content = if ($Mode -eq 'staged') { git show ":$file" } else { Get-Content -LiteralPath $file -Raw }
            if (($content -join "`n") -match $forbidden) { throw "Privacy pattern found in $Mode file: $file" }
        }
    }
    Write-Host "privacy check passed ($Mode)"
} finally {
    Pop-Location
}
