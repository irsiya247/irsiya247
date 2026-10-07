$ErrorActionPreference = 'Stop'

$ControlRepoUrl = 'https://github.com/irsiya247/stl-automate-tools.git'
$InstallRoot = Join-Path $env:LOCALAPPDATA 'STLAutomate\CodexController'
$Controller = Join-Path $InstallRoot 'codex-controller\controller.ps1'
$TargetRepo = 'C:\Users\irsiy\Documents\Codex\credit-accuracy-c0'
$StateDir = Join-Path $env:LOCALAPPDATA 'STLAutomate\CodexControllerState'
$LogPath = Join-Path $StateDir 'controller.log'

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

$existing = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*codex-controller\controller.ps1*' }

if (-not $existing) {
    if (Test-Path -LiteralPath (Join-Path $InstallRoot '.git')) {
        git -C $InstallRoot fetch origin main
        if ($LASTEXITCODE -ne 0) { throw 'Failed to fetch controller repository.' }
        git -C $InstallRoot reset --hard origin/main
        if ($LASTEXITCODE -ne 0) { throw 'Failed to update controller repository.' }
    } else {
        New-Item -ItemType Directory -Path (Split-Path $InstallRoot -Parent) -Force | Out-Null
        git clone $ControlRepoUrl $InstallRoot
        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to clone the private controller repository. Verify this Windows user is authenticated to GitHub.'
        }
    }
}

if (-not (Test-Path -LiteralPath $Controller)) {
    throw "Controller script missing at $Controller"
}

$startup = [Environment]::GetFolderPath('Startup')
$launcher = Join-Path $startup 'STL-Codex-Controller.cmd'
$launcherBody = @'
@echo off
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%LOCALAPPDATA%\STLAutomate\CodexController\codex-controller\controller.ps1"
'@
[IO.File]::WriteAllText($launcher, $launcherBody, [Text.Encoding]::ASCII)

if (-not $existing) {
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $Controller
    )
}

Start-Sleep -Seconds 4

$running = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*codex-controller\controller.ps1*' }

if (-not $running) {
    throw 'Controller process did not remain running. Check the local controller log.'
}

New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

Write-Host ''
Write-Host 'STL CODEX CONTROLLER: READY'
Write-Host "Install: $InstallRoot"
Write-Host "Startup: $launcher"
Write-Host "Target:  $TargetRepo"
Write-Host "Log:     $LogPath"
Write-Host ''
Write-Host 'No Desktop Commander is required.'
