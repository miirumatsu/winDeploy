[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Version,
    [string] $NssmPath = 'nssm.exe',
    [string] $ServiceName = 'PM2',
    [string] $Pm2Home = 'C:\ProgramData\pm2'
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

function Start-NssmService {
    param(
        [Parameter(Mandatory = $true)]
        [string] $NssmExecutable,
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    & $NssmExecutable start $Name
    $startExitCode = $LASTEXITCODE

    try {
        $service = Get-Service -Name $Name -ErrorAction Stop
        $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(60))
    } catch {
        $currentStatus = (Get-Service -Name $Name -ErrorAction SilentlyContinue).Status
        throw "NSSM start returned exit code $startExitCode and service status '$currentStatus'. $($_.Exception.Message)"
    }

    Write-Host "Service '$Name' is running."
}

$Version = $Version.Trim().TrimStart('v')
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "Invalid Node.js version: $Version"
}

& nvm use $Version --no-install *> $null
$useExitCode = $LASTEXITCODE

if ($useExitCode -ne 0) {
    Write-Host "Node.js $Version is not installed. Installing it with NVM for Windows..."
    Invoke-Native -FilePath 'nvm' -Arguments @('install', $Version)
    Invoke-Native -FilePath 'nvm' -Arguments @('use', $Version, '--no-install')
}

if ((& node --version).Trim() -ne "v$Version") {
    throw "NVM selected a Node.js version other than $Version."
}

Invoke-Native -FilePath 'npm' -Arguments @('install', '--global', 'pm2')

$nodeExecutable = (& node -p 'process.execPath').Trim()
$globalRoot = (& npm root --global).Trim()
$pm2Script = Join-Path $globalRoot 'pm2\bin\pm2'

if (-not (Test-Path -LiteralPath $nodeExecutable)) {
    throw "Node.js executable was not found: $nodeExecutable"
}
if (-not (Test-Path -LiteralPath $pm2Script)) {
    throw "PM2 script was not found: $pm2Script"
}

$versionFile = Join-Path $Pm2Home 'pm2-node-version.txt'
New-Item -ItemType Directory -Path $Pm2Home -Force | Out-Null
[Environment]::SetEnvironmentVariable('PM2_HOME', $Pm2Home, 'Machine')
$env:PM2_HOME = $Pm2Home
Set-Content -LiteralPath $versionFile -Value $Version -NoNewline

Invoke-Native -FilePath $NssmPath -Arguments @('stop', $ServiceName)
Invoke-Native -FilePath $NssmPath -Arguments @('set', $ServiceName, 'AppEnvironmentExtra', "PM2_HOME=$Pm2Home", "PM2_NODE_VERSION=$Version", "PM2_NODE_EXECUTABLE=$nodeExecutable", "PM2_SCRIPT=$pm2Script")
Start-NssmService -NssmExecutable $NssmPath -Name $ServiceName

Write-Host "PM2 service $ServiceName now uses Node.js $Version."
Write-Host "Node.js: $nodeExecutable"
Write-Host "PM2 script: $pm2Script"
