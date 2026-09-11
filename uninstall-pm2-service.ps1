[CmdletBinding()]
param(
    [string] $NssmPath = 'nssm.exe',
    [string] $ServiceName = 'PM2'
)

$ErrorActionPreference = 'Stop'

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,
        [string[]] $Arguments = @()
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE."
    }
}

if (-not (Get-Command $NssmPath -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $NssmPath)) {
    throw "NSSM was not found: $NssmPath"
}

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Host "Service not found; nothing to uninstall: $ServiceName"
    exit 0
}

if ($service.Status -ne 'Stopped') {
    Invoke-Native -FilePath $NssmPath -Arguments @('stop', $ServiceName)
}

Invoke-Native -FilePath $NssmPath -Arguments @('remove', $ServiceName, 'confirm')

Write-Host "Removed NSSM service: $ServiceName"
Write-Host 'PM2_HOME, saved process state, logs, Node.js installations, and global PM2 packages were preserved.'
