param([switch]$Open)

$ErrorActionPreference = 'Stop'
$executablePath = Join-Path $PSScriptRoot 'AirLauncher.exe'
if (-not (Test-Path -LiteralPath $executablePath)) { throw 'Build AirLauncher.exe first with Build.ps1.' }
$shortcutService = New-Object -ComObject WScript.Shell
$desktopPath = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktopPath 'Air Launcher.lnk'
$shortcut = $shortcutService.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $executablePath
$shortcut.Arguments = ''
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = 'Open a project in Codex, Claude, or Gemini using JetBrains AI'
$shortcut.IconLocation = $executablePath + ',0'
$shortcut.Save()
Write-Output "Created $shortcutPath"

if ($Open) {
    Start-Process -FilePath $executablePath -WindowStyle Normal
}
