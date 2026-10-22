# Installs (or updates) Bot Party on Windows from the GitHub releases.
#
#   irm https://raw.githubusercontent.com/AnCarsenat/bot-party/main/install.ps1 | iex
#
# Nightly build, or uninstall:
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/AnCarsenat/bot-party/main/install.ps1))) -Nightly
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/AnCarsenat/bot-party/main/install.ps1))) -Uninstall
#
# The game goes to %LOCALAPPDATA%\BotParty, with Start menu and desktop shortcuts.
# Run it again to update. No admin rights needed.
param(
	[switch]$Nightly,
	[switch]$Uninstall,
	[string]$Repo = "AnCarsenat/bot-party"
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # much faster downloads

$dir = Join-Path $env:LOCALAPPDATA "BotParty"
$startMenu = Join-Path ([Environment]::GetFolderPath("Programs")) "Bot Party.lnk"
$desktop = Join-Path ([Environment]::GetFolderPath("Desktop")) "Bot Party.lnk"

if ($Uninstall) {
	Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $dir, $startMenu, $desktop
	Write-Host "Bot Party removed. (Your saves and settings stay in %APPDATA%\Godot\app_userdata\Bot Party.)"
	return
}

$api = if ($Nightly) { "https://api.github.com/repos/$Repo/releases/tags/nightly" } else { "https://api.github.com/repos/$Repo/releases/latest" }
try {
	$release = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "bot-party-installer" }
} catch {
	throw "Couldn't find a release of $Repo. (No release yet? Try -Nightly.)"
}
$asset = $release.assets | Where-Object { $_.name -like "*-windows.zip" } | Select-Object -First 1
if (-not $asset) { throw "That release has no Windows build." }

Write-Host "Downloading $($release.name)..."
$zip = Join-Path $env:TEMP "BotParty-download.zip"
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -Headers @{ "User-Agent" = "bot-party-installer" }

Get-Process -Name "BotParty" -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $dir
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Expand-Archive -Path $zip -DestinationPath $dir -Force
Remove-Item $zip
$exe = Join-Path $dir "BotParty.exe"
Unblock-File -Path $exe -ErrorAction SilentlyContinue   # downloaded file: skip the SmartScreen block

$shell = New-Object -ComObject WScript.Shell
foreach ($path in @($startMenu, $desktop)) {
	$link = $shell.CreateShortcut($path)
	$link.TargetPath = $exe
	$link.WorkingDirectory = $dir
	$link.Description = "Bot Party"
	$link.Save()
}
Write-Host "Installed $($release.name). Start it from the Start menu or the desktop shortcut."
