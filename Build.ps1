$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $appDirectory = Join-Path $env:USERPROFILE '.air-launcher'
    $null = New-Item -ItemType Directory -Path $appDirectory -Force
    $toolDirectory = Join-Path $appDirectory 'tools'
    $previousTools = Join-Path $env:LOCALAPPDATA 'AirLauncher\tools'
    if ((-not (Test-Path -LiteralPath $toolDirectory)) -and (Test-Path -LiteralPath $previousTools)) {
        Copy-Item -LiteralPath $previousTools -Destination $toolDirectory -Recurse
    }
    $settingsPath = Join-Path $appDirectory 'settings.json'
    $previousSettings = Join-Path $env:LOCALAPPDATA 'AirLauncher\settings.json'
    if ((-not (Test-Path -LiteralPath $settingsPath)) -and (Test-Path -LiteralPath $previousSettings)) {
        Copy-Item -LiteralPath $previousSettings -Destination $settingsPath
    }
    $localCodex = Join-Path $toolDirectory 'node_modules\.bin\codex.cmd'
    $codexPackageJson = Join-Path $toolDirectory 'node_modules\@openai\codex\package.json'
    $needsCodexInstall = $true
    if ((Test-Path -LiteralPath $localCodex) -and (Test-Path -LiteralPath $codexPackageJson)) {
        try {
            $installedVersion = (Get-Content -LiteralPath $codexPackageJson -Raw | ConvertFrom-Json).version
            if ($installedVersion -ge '0.166.0') {
                $needsCodexInstall = $false
            }
        }
        catch { }
    }
    if ($needsCodexInstall) {
        & rtk npm install --prefix $toolDirectory '@openai/codex@0.166.0'
        if ($LASTEXITCODE -ne 0) { throw 'The launcher Codex installation failed.' }
    }

    & rtk cargo build --release --locked
    if ($LASTEXITCODE -ne 0) { throw 'Rust compilation failed.' }

    $releaseExecutable = Join-Path $PSScriptRoot 'target\release\AirLauncher.exe'
    $terminalCheck = Start-Process -FilePath $releaseExecutable -ArgumentList '--verify-terminal' -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -Wait -PassThru
    if ($terminalCheck.ExitCode -ne 0) { throw 'Windows Terminal handoff check failed. See %USERPROFILE%\.air-launcher\terminal-check-error.txt.' }

    $outputPath = Join-Path $PSScriptRoot 'AirLauncher.exe'
    $runningLaunchers = @(Get-Process AirLauncher -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $outputPath })
    foreach ($runningLauncher in $runningLaunchers) {
        $null = $runningLauncher.CloseMainWindow()
        if (-not $runningLauncher.WaitForExit(5000)) { throw 'Close the Air Launcher window so its executable can be replaced.' }
    }
    if (Test-Path -LiteralPath $outputPath) {
        $backupDirectory = Join-Path $PSScriptRoot 'legacy'
        $null = New-Item -ItemType Directory -Path $backupDirectory -Force
        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item -LiteralPath $outputPath -Destination (Join-Path $backupDirectory "AirLauncher-$timestamp.exe")
    }
    Copy-Item -LiteralPath .\target\release\AirLauncher.exe -Destination $outputPath -Force
    Write-Output "Built and checked $outputPath"
}
finally { Pop-Location }
