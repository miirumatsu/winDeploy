# Windows PM2/NSSM deployment

This directory contains the machine-level deployment files for a generic PM2 service. NSSM manages PM2; PM2 manages applications from multiple repositories.

```text
NSSM service: PM2
    └── pm2-service.ps1
            └── pm2 resurrect
                ├── project-a
                ├── project-b
                └── other projects
```

The service does not contain a repository path. Each project remains responsible for its own `ecosystem.config.cjs` and `.nvmrc`.

## Prerequisites

- Windows PowerShell
- NVM for Windows v2
- NSSM available as `nssm.exe` or supplied with `-NssmPath`
- A Windows service account with access to the PM2 home directory, Node installations, project directories, `.env` files, and required application caches

NVM for Windows v2 documentation: <https://docs.nvm-windows.com>

The PM2 service uses the Node version in `pm2-node-version.txt`. This is separate from a project’s `.nvmrc`. The service runtime and project runtimes can be different.

## Install the generic PM2 service

Run the following from an elevated PowerShell session using the account that will run the service, or ensure that the selected NVM installation and global PM2 package are available to the service account:

```powershell
$winDeployRoot = 'D:\Tools\winDeploy'
Set-Location $winDeployRoot
.\install-pm2-service.ps1 -NssmPath 'D:\Tools\nssm\win64\nssm.exe' -StartService
```

The installer:

1. Reads the PM2 service Node version from `pm2-node-version.txt`.
2. Selects that version with `nvm use <version> --no-install`.
3. Installs/verifies PM2 for that Node version.
4. Resolves the absolute `node.exe` and PM2 script paths.
5. Installs the generic NSSM service named `PM2`.
6. Uses `C:\ProgramData\pm2` as the shared `PM2_HOME`.
7. Configures service logs and automatic recovery.

Configure the NSSM service account after installation if it is different from the account used during setup. The account must be able to read the resolved Node and PM2 paths.

The service receives these environment variables:

```text
PM2_HOME=C:\ProgramData\pm2
PM2_NODE_VERSION=24.20.0
PM2_NODE_EXECUTABLE=<absolute node.exe path>
PM2_SCRIPT=<absolute PM2 script path>
```

The wrapper invokes `PM2_SCRIPT` using `PM2_NODE_EXECUTABLE`, so changing the PM2 service Node version does not depend on the service account's interactive `PATH`.

## Register an application

Use the same service account and shared `PM2_HOME`:

```powershell
$env:PM2_HOME = 'C:\ProgramData\pm2'

$projectRoot = Read-Host 'Application project root'
Set-Location $projectRoot
nvm use (Get-Content -LiteralPath '.nvmrc' -Raw).Trim() --no-install
pm2 start (Join-Path $projectRoot 'ecosystem.config.cjs') --update-env
pm2 save
```

Repeat the registration steps for each application. Every application should provide its own `ecosystem.config.cjs` and `.nvmrc`. The saved PM2 process list is stored under `C:\ProgramData\pm2` and is restored when the NSSM service starts.

## Change the PM2 service Node version

The PM2 service has its own version pin. Change it with:

```powershell
$winDeployRoot = 'D:\Tools\winDeploy'
Set-Location $winDeployRoot
.\set-pm2-node-version.ps1 -Version 25.2.1 -NssmPath 'D:\Tools\nssm\win64\nssm.exe'
```

The script:

- Installs the target Node version with NVM when it is not already installed.
- Installs PM2 under that Node version.
- Updates the shared PM2 version record.
- Updates NSSM’s explicit Node and PM2 script paths.
- Restarts the generic PM2 service.

The target version must be available from the configured NVM download source. If installation fails, verify network, proxy, mirror, and service-account permissions.

The command can therefore be used directly for both installed and new versions:

```powershell
.\set-pm2-node-version.ps1 -Version 25.2.1 -NssmPath 'D:\Tools\nssm\win64\nssm.exe'
```

## Uninstall the PM2 service

Remove only the generic NSSM service with:

```powershell
Set-Location D:\Tools\winDeploy
.\uninstall-pm2-service.ps1 -NssmPath 'D:\Tools\nssm\win64\nssm.exe'
```

The uninstall script stops and removes the `PM2` service but preserves `C:\ProgramData\pm2`, including the saved PM2 process list and logs. This allows the service to be reinstalled later without losing registered applications.

Removing the PM2 data, global PM2 packages, or NVM-managed Node.js versions is a separate manual cleanup operation and is intentionally not performed by this script.

Applications do not need to change when the PM2 service runtime changes. An application runtime change is handled independently by updating that application’s `.nvmrc`, ensuring the version is installed, and refreshing that application’s PM2 entry:

```powershell
$projectRoot = Read-Host 'Application project root'
pm2 startOrRestart (Join-Path $projectRoot 'ecosystem.config.cjs') --update-env
pm2 save
```

## Deployment workflow

For a project deployment:

1. Build and test the project.
2. Deploy its application files without replacing the server-side `.env`.
3. Run `npm ci --omit=dev` with the project’s `.nvmrc` version.
4. Run `pm2 startOrRestart <project>\ecosystem.config.cjs --update-env`.
5. Run `pm2 save` so the new process definition survives a reboot.
6. Verify the application health endpoint or port.

Do not configure NSSM with a project ecosystem path. Do not use `pm2-windows-startup` together with this service. NSSM is the startup mechanism, and the shared PM2 saved process list is the source of applications restored at boot.

## Diagnostics

```powershell
Get-Service PM2
$env:PM2_HOME = 'C:\ProgramData\pm2'
pm2 list
pm2 prettylist
Get-Content C:\ProgramData\pm2\pm2-service-error.log -Tail 100
nvm env --json
nvm doctor
```

If a project is missing after reboot, register it using the service account and run `pm2 save` with the shared `PM2_HOME`.
