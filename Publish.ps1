$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    # Bump before compiling so the title, Windows metadata, and published folder agree.
    $manifestPath = Join-Path $PSScriptRoot 'Cargo.toml'
    $manifest = [IO.File]::ReadAllText($manifestPath)
    $versionPattern = '(?ms)(^\[package\]\s*.*?^version\s*=\s*")(\d+)\.(\d+)\.(\d+)(")'
    $versionMatch = [regex]::Match($manifest, $versionPattern)
    if (-not $versionMatch.Success) { throw 'Cargo.toml must declare a major.minor.patch package version.' }
    $previousVersion = '{0}.{1}.{2}' -f $versionMatch.Groups[2].Value, $versionMatch.Groups[3].Value, $versionMatch.Groups[4].Value
    $version = '{0}.{1}.{2}' -f $versionMatch.Groups[2].Value, $versionMatch.Groups[3].Value, ([int]$versionMatch.Groups[4].Value + 1)
    $publishDirectory = Join-Path $PSScriptRoot 'publish'
    $versionDirectory = Join-Path $publishDirectory $version
    if (Test-Path -LiteralPath $versionDirectory) { throw "Version $version is already published. Existing releases will not be overwritten." }
    $updatedManifest = $manifest.Substring(0, $versionMatch.Index) + $versionMatch.Groups[1].Value + $version + $versionMatch.Groups[5].Value + $manifest.Substring($versionMatch.Index + $versionMatch.Length)
    [IO.File]::WriteAllText($manifestPath, $updatedManifest, (New-Object Text.UTF8Encoding($false)))
    Write-Output "Bumped Air Launcher $previousVersion -> $version"
    & cargo update --workspace --offline
    if ($LASTEXITCODE -ne 0) { throw 'Could not synchronize Cargo.lock with the incremented version.' }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Build.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Build and terminal verification failed.' }

    $null = New-Item -ItemType Directory -Path $versionDirectory -Force
    $executable = Join-Path $publishDirectory 'AirLauncher.exe'
    $runningLaunchers = @(Get-Process AirLauncher -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $executable })
    foreach ($runningLauncher in $runningLaunchers) {
        $null = $runningLauncher.CloseMainWindow()
        if (-not $runningLauncher.WaitForExit(5000)) { throw 'Close the published Air Launcher window so its executable can be replaced.' }
    }
    $versionedExecutable = Join-Path $versionDirectory 'AirLauncher.exe'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'AirLauncher.exe') -Destination $versionedExecutable
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'AirLauncher.exe') -Destination $executable -Force
    Write-Output "Published Air Launcher v${version}: $versionedExecutable"
    Write-Output "Latest single-file app: $executable"
    Write-Output 'Copy this EXE to the destination PC. Agent tools and JetBrains sign-in are still required.'
}
finally { Pop-Location }
