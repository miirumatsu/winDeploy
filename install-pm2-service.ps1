[CmdletBinding()]
param(
    [string] $NssmPath = 'nssm.exe',
    [string] $ServiceName = 'PM2',
    [string] $Pm2Home = 'C:\ProgramData\pm2',
    [switch] $StartService
)

$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script from an elevated PowerShell session.'
    }
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,
        [Parameter(Mandatory = $false)]
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

Assert-Administrator

if (-not (Get-Command $NssmPath -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $NssmPath)) {
    throw "NSSM was not found: $NssmPath"
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$versionFile = Join-Path $scriptRoot 'pm2-node-version.txt'
$wrapperSource = Join-Path $scriptRoot 'pm2-service.ps1'

if (-not (Test-Path -LiteralPath $versionFile)) {
    throw "PM2 version file was not found: $versionFile"
}

$nodeVersion = (Get-Content -LiteralPath $versionFile -Raw).Trim().TrimStart('v')
if ($nodeVersion -notmatch '^\d+\.\d+\.\d+$') {
    throw "Invalid PM2 Node.js version: $nodeVersion"
}

Invoke-Native -FilePath 'nvm' -Arguments @('use', $nodeVersion, '--no-install')

$activeVersion = (& node --version).Trim().TrimStart('v')
if ($activeVersion -ne $nodeVersion) {
    throw "NVM selected Node.js $activeVersion instead of $nodeVersion."
}

Write-Host "Installing/verifying PM2 for Node.js $nodeVersion..."
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

New-Item -ItemType Directory -Path $Pm2Home -Force | Out-Null
[Environment]::SetEnvironmentVariable('PM2_HOME', $Pm2Home, 'Machine')
$env:PM2_HOME = $Pm2Home
$wrapperTarget = Join-Path $Pm2Home 'pm2-service.ps1'
Copy-Item -LiteralPath $wrapperSource -Destination $wrapperTarget -Force

if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
    throw "The service already exists: $ServiceName. Remove it first or update it with set-pm2-node-version.ps1."
}

Invoke-Native -FilePath $NssmPath -Arguments @('install', $ServiceName, "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe")
Invoke-Native -FilePath $NssmPath -Arguments @('set', $ServiceName, 'AppDirectory', $Pm2Home)
Invoke-Native -FilePath $NssmPath -Arguments @('set', $ServiceName, 'AppParameters', "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$wrapperTarget`"")
Invoke-Native -FilePath $NssmPath -Arguments @('set', $ServiceName, 'AppEnvironmentExtra', "PM2_HOME=$Pm2Home", "PM2_NODE_VERSION=$nodeVersion", "PM2_NODE_EXECUTABLE=$nodeExecutable", "PM2_SCRIPT=$pm2Script")
Invoke-Native -FilePath $NssmPath -Arguments @('set', $ServiceName, 'AppStdout', (Join-Path $Pm2Home 'pm2-service-out.log'))
Invoke-Native -FilePath $NssmPath -Arguments @('set', $ServiceName, 'AppStderr', (Join-Path $Pm2Home 'pm2-service-error.log'))
Invoke-Native -FilePath $NssmPath -Arguments @('set', $ServiceName, 'AppRotateFiles', '1')
Invoke-Native -FilePath $NssmPath -Arguments @('set', $ServiceName, 'AppRotateOnline', '1')
Invoke-Native -FilePath $NssmPath -Arguments @('set', $ServiceName, 'AppRotateBytes', '10485760')
Invoke-Native -FilePath $NssmPath -Arguments @('set', $ServiceName, 'AppExit', 'Default', 'Restart')
Invoke-Native -FilePath $NssmPath -Arguments @('set', $ServiceName, 'AppThrottle', '5000')
Invoke-Native -FilePath $NssmPath -Arguments @('set', $ServiceName, 'Start', 'SERVICE_AUTO_START')

if ($StartService) {
    Start-NssmService -NssmExecutable $NssmPath -Name $ServiceName
}

Write-Host "NSSM PM2 service configured: $ServiceName"
Write-Host "PM2_HOME: $Pm2Home"
Write-Host "Node.js: $nodeExecutable"
Write-Host "PM2 script: $pm2Script"
