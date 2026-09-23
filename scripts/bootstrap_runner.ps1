param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("register", "register-and-run-once", "remove")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$Repo,

    [string]$Name,
    [string]$Labels,
    [string]$Dir,
    [string]$Work = "_work",
    [string]$Version = "latest",
    [switch]$ForceDownload,
    [switch]$RunAsService,
    [switch]$NoService,
    [switch]$PromptService
)

$ErrorActionPreference = "Stop"

function Require-Command {
    param([string]$CommandName)
    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        throw "Missing required command: $CommandName"
    }
}

Require-Command "gh"

if (-not $Name) {
    $Name = "$($env:COMPUTERNAME)-windows"
}

$arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { throw "Unsupported architecture" }

if (-not $Labels) {
    $Labels = "self-hosted,windows,$arch"
}

$repoSlug = $Repo.Replace("/", "_")
if (-not $Dir) {
    $Dir = Join-Path $env:USERPROFILE ".gh-runners\$repoSlug\$Name"
}

if ($Version -eq "latest") {
    $tag = (gh api repos/actions/runner/releases/latest --jq .tag_name).Trim()
    $Version = $tag.TrimStart("v")
}

$archive = "actions-runner-win-$arch-$Version.zip"
$downloadUrl = "https://github.com/actions/runner/releases/download/v$Version/$archive"

New-Item -ItemType Directory -Path $Dir -Force | Out-Null
Set-Location $Dir

if ($Action -eq "remove") {
    if (-not (Test-Path ".\config.cmd")) {
        Write-Host "No runner config found in $Dir. Nothing to remove."
        exit 0
    }

    $removeToken = (gh api -X POST "repos/$Repo/actions/runners/remove-token" --jq .token).Trim()
    & .\config.cmd remove --unattended --token $removeToken
    Write-Host "Runner removed from $Repo."
    exit 0
}

if ($ForceDownload -or -not (Test-Path ".\config.cmd")) {
    Get-ChildItem -Path . -Filter "*.zip" -ErrorAction SilentlyContinue | Remove-Item -Force
    Invoke-WebRequest -Uri $downloadUrl -OutFile $archive
    Expand-Archive -Path $archive -DestinationPath . -Force
}

$registrationToken = (gh api -X POST "repos/$Repo/actions/runners/registration-token" --jq .token).Trim()

$configArgs = @(
    "--url", "https://github.com/$Repo",
    "--token", $registrationToken,
    "--name", $Name,
    "--labels", $Labels,
    "--work", $Work,
    "--unattended",
    "--replace"
)

if ($Action -eq "register-and-run-once") {
    $configArgs += "--ephemeral"
    $NoService = $true
}

& .\config.cmd @configArgs

$useService = $false
if ($RunAsService) {
    $useService = $true
}
if ($NoService) {
    $useService = $false
}
if ($PromptService -and -not $NoService -and $Action -ne "register-and-run-once") {
    $choice = Read-Host "Install and start as service on this machine? [y/N]"
    if ($choice -match '^[Yy]$') {
        $useService = $true
    }
}

if ($useService) {
    if (Test-Path ".\svc.cmd") {
        & .\svc.cmd install
        & .\svc.cmd start
        Write-Host "Runner service installed and started."
    }
    else {
        Write-Host "svc.cmd is not available on this platform."
    }
}
else {
    if ($Action -eq "register-and-run-once") {
        Write-Host "Starting ephemeral runner for one job..."
        & .\run.cmd
    }
    else {
        Write-Host "Runner configured. Start it with:"
        Write-Host "  cd $Dir"
        Write-Host "  .\run.cmd"
    }
}

Write-Host "Done. Runner '$Name' registered for $Repo with labels: $Labels"
