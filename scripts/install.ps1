[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.:-]*$')]
    [string]$DeviceHost,

    [Parameter(Mandatory = $true)]
    [string]$IdentityFile
)

$ErrorActionPreference = 'Stop'
$Compatibility = Join-Path (Split-Path -Parent $PSScriptRoot) 'compatibility.env'
function Get-CompatibilityValue {
    param([Parameter(Mandatory = $true)][string]$Name)
    $match = Get-Content -LiteralPath $Compatibility |
        Where-Object { $_ -match "^$([regex]::Escape($Name))=(.+)$" } |
        Select-Object -First 1
    if (-not $match) { throw "compatibility.env does not define $Name" }
    return ($match -split '=', 2)[1]
}

$Version = Get-CompatibilityValue PROJECT_VERSION
$Project = 'MrSmaugerson05/remarkable-remote-share'
$TailscaleVersion = Get-CompatibilityValue TAILSCALE_VERSION
$TailscaleSha256 = Get-CompatibilityValue TAILSCALE_ARM64_SHA256
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'PROJECT_VERSION is not a release version' }
if ($TailscaleSha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'TAILSCALE_ARM64_SHA256 is invalid' }
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("remarkable-remote-share-" + [guid]::NewGuid().ToString('N'))
$RemoteStage = "/home/root/remote-share-upload-$([guid]::NewGuid().ToString('N'))"

function Invoke-Checked {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Program exited with code $LASTEXITCODE"
    }
}

function Assert-Hash {
    param([string]$Path, [string]$Expected)
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    if ($actual -ne $Expected.ToLowerInvariant()) {
        throw "SHA-256 mismatch for $([System.IO.Path]::GetFileName($Path))"
    }
}

if (-not (Test-Path -LiteralPath $IdentityFile -PathType Leaf)) {
    throw "SSH identity file not found: $IdentityFile"
}
foreach ($command in 'ssh', 'scp', 'tar') {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command is missing: $command"
    }
}

New-Item -ItemType Directory -Path $TempRoot | Out-Null
try {
    $archive = Join-Path $TempRoot "remarkable-remote-share-$Version.tar.gz"
    $base = "https://github.com/$Project/releases/download/v$Version"
    Invoke-WebRequest -UseBasicParsing -Uri "$base/remarkable-remote-share-$Version.tar.gz" -OutFile $archive
    Invoke-WebRequest -UseBasicParsing -Uri "$base/SHA256SUMS" -OutFile (Join-Path $TempRoot 'SHA256SUMS')
    $line = Get-Content -LiteralPath (Join-Path $TempRoot 'SHA256SUMS') |
        Where-Object { $_ -match "  remarkable-remote-share-$([regex]::Escape($Version))\.tar\.gz$" } |
        Select-Object -First 1
    if (-not $line) { throw 'Release checksum is missing' }
    Assert-Hash -Path $archive -Expected (($line -split '\s+')[0])

    $tailscaleArchive = Join-Path $TempRoot "tailscale_$($TailscaleVersion)_arm64.tgz"
    Invoke-WebRequest -UseBasicParsing -Uri "https://pkgs.tailscale.com/stable/tailscale_$($TailscaleVersion)_arm64.tgz" -OutFile $tailscaleArchive
    Assert-Hash -Path $tailscaleArchive -Expected $TailscaleSha256

    Invoke-Checked tar @('-xzf', $archive, '-C', $TempRoot)
    Invoke-Checked tar @('-xzf', $tailscaleArchive, '-C', $TempRoot)
    $payload = Join-Path $TempRoot "remarkable-remote-share-$Version"
    $tailscaleDir = Get-ChildItem -LiteralPath $TempRoot -Directory -Filter "tailscale_$($TailscaleVersion)_arm64" | Select-Object -First 1
    if (-not $tailscaleDir) { throw 'Tailscale archive layout was not recognized' }
    Copy-Item -LiteralPath (Join-Path $tailscaleDir.FullName 'tailscale') -Destination $payload
    Copy-Item -LiteralPath (Join-Path $tailscaleDir.FullName 'tailscaled') -Destination $payload

    $target = "root@$DeviceHost"
    $sshArgs = @('-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-i', $IdentityFile)
    Invoke-Checked ssh ($sshArgs + @($target, "install -d -m 700 '$RemoteStage'"))
    Push-Location $payload
    try {
        Invoke-Checked scp (@('-q', '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-i', $IdentityFile, '-r', '.', "${target}:$RemoteStage/"))
    } finally {
        Pop-Location
    }
    Invoke-Checked ssh ($sshArgs + @($target, "chmod 755 '$RemoteStage/device-install.sh' && '$RemoteStage/device-install.sh' '$RemoteStage'"))

    Write-Host ''
    Write-Host 'Tailscale authentication is interactive. Open the URL printed below in your browser.'
    Invoke-Checked ssh ($sshArgs + @('-t', $target, '/home/root/remote-share/remote-share-control auth'))
    Invoke-Checked ssh ($sshArgs + @($target, '/home/root/remote-share/remote-share-control off'))
    Write-Host 'Installation finished. Sharing is OFF. Reboot with the normal three-button XOVI start sequence.'
} finally {
    try {
        if ($DeviceHost -and $IdentityFile -and (Test-Path -LiteralPath $IdentityFile)) {
            & ssh -o BatchMode=yes -o IdentitiesOnly=yes -i $IdentityFile "root@$DeviceHost" "rm -rf '$RemoteStage'" 2>$null
        }
    } catch {}
    $resolvedTemp = [System.IO.Path]::GetFullPath($TempRoot)
    $systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemp).StartsWith('remarkable-remote-share-')) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
