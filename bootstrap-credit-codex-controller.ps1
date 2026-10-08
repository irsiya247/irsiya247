$ErrorActionPreference = 'Stop'

$ControlRepoUrl = 'https://github.com/irsiya247/stl-automate-tools.git'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'STLAutomate\CodexController'
$Controller = Join-Path $InstallRoot 'codex-controller\controller.ps1'
$Supervisor = Join-Path $InstallRoot 'codex-controller\supervisor.ps1'
$TargetRepo = 'C:\Users\irsiy\Documents\Codex\credit-accuracy-c0'
$StateDir = Join-Path $env:LOCALAPPDATA 'STLAutomate\CodexControllerState'
$LogPath = Join-Path $StateDir 'supervisor.log'

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is required but was not found."
    }
}

Require-Command 'git'
if (-not (Test-Path -LiteralPath (Join-Path $TargetRepo '.git'))) {
    throw "Credit Accuracy repository not found at $TargetRepo"
}

$codexRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
$codexExe = Get-ChildItem -LiteralPath $codexRoot -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'codex.exe' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if (-not $codexExe) {
    throw "Codex executable not found under $codexRoot"
}

if (Test-Path -LiteralPath (Join-Path $InstallRoot '.git')) {
    $dirty = @(git -C $InstallRoot status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count -gt 0) {
        throw 'Controller repository is dirty. No files were reset. Review uncommitted control artifacts before updating.'
    }
    git -C $InstallRoot fetch origin main
    if ($LASTEXITCODE -ne 0) { throw 'Failed to fetch controller source.' }
    git -C $InstallRoot merge --ff-only origin/main
    if ($LASTEXITCODE -ne 0) { throw 'Controller repository diverged. No history was discarded.' }
} else {
    New-Item -ItemType Directory -Path (Split-Path $InstallRoot -Parent) -Force | Out-Null
    git clone $ControlRepoUrl $InstallRoot
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not clone the private controller repository using existing GitHub credentials.'
    }
}

if (-not (Test-Path -LiteralPath $Controller -PathType Leaf) -or
        -not (Test-Path -LiteralPath $Supervisor -PathType Leaf)) {
    throw 'Controller or supervisor script is missing after source update.'
}

New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

$startup = [Environment]::GetFolderPath('Startup')
$launcher = Join-Path $startup 'STL-Codex-Controller.cmd'
$launcherBody = @'
@echo off
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%LOCALAPPDATA%\STLAutomate\CodexController\codex-controller\supervisor.ps1"
'@
[IO.File]::WriteAllText($launcher, $launcherBody, [Text.Encoding]::ASCII)

# The supervisor is the only launcher from this point forward.
$existing = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -in @('powershell.exe', 'pwsh.exe') -and
        $_.CommandLine -like '*CodexController\codex-controller\supervisor.ps1*'
    })
# Restart only this exact controller supervisor so upgraded mutex-recovery code
# is picked up immediately. Never stop an unrelated Codex session or repository worker.
if ($existing.Count -gt 0) {
    foreach ($instance in $existing) {
        Write-Host ('Restarting prior controller supervisor PID {0}' -f $instance.ProcessId)
        Stop-Process -Id $instance.ProcessId -Force -ErrorAction Stop
    }
    Start-Sleep -Seconds 2
}
$args = '-NoProfile -ExecutionPolicy Bypass -File "' + $Supervisor + '"'
$new = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList $args -PassThru
Start-Sleep -Seconds 5
$new.Refresh()
if ($new.HasExited) {
    $detail = ''
    if (Test-Path -LiteralPath $LogPath) {
        $detail = (Get-Content -LiteralPath $LogPath -Tail 15) -join [Environment]::NewLine
    }
    throw ('Supervisor exited during bootstrap. ' + $detail)
}
Write-Host ('Supervisor PID: {0}' -f $new.Id)

Write-Host ''
Write-Host 'STL CODEX SUPERVISOR: ACTIVE (controller execution pending verification)'
Write-Host "Controller: $Controller"
Write-Host "Log:        $LogPath"
Write-Host "Startup:    $launcher"
Write-Host ''
Write-Host 'The supervisor restarts the local Codex controller after unexpected exits.'
Write-Host 'No Desktop Commander is required.'
