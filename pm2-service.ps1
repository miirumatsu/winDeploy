[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Invoke-Pm2 {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    & $env:PM2_NODE_EXECUTABLE $env:PM2_SCRIPT @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "PM2 command failed with exit code $LASTEXITCODE : pm2 $($Arguments -join ' ')"
    }
}

if (-not $env:PM2_HOME) {
    throw 'PM2_HOME is not configured.'
}

if (-not $env:PM2_NODE_EXECUTABLE -or -not (Test-Path -LiteralPath $env:PM2_NODE_EXECUTABLE)) {
    throw "PM2_NODE_EXECUTABLE is not configured or does not exist: $env:PM2_NODE_EXECUTABLE"
}

if (-not $env:PM2_SCRIPT -or -not (Test-Path -LiteralPath $env:PM2_SCRIPT)) {
    throw "PM2_SCRIPT is not configured or does not exist: $env:PM2_SCRIPT"
}

# Restore every project previously registered in the shared PM2_HOME.
Invoke-Pm2 -Arguments @('resurrect')

# Keep this process alive so NSSM can supervise PM2. If PM2 stops responding,
# exit and let NSSM restart this wrapper and attempt resurrection again.
while ($true) {
    try {
        Invoke-Pm2 -Arguments @('ping')
    } catch {
        Write-Error $_
        exit 1
    }

    Start-Sleep -Seconds 10
}
