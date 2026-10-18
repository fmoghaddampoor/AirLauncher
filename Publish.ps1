$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Build.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Build and terminal verification failed.' }

    $publishDirectory = Join-Path $PSScriptRoot 'publish'
    $null = New-Item -ItemType Directory -Path $publishDirectory -Force
    $executable = Join-Path $publishDirectory 'AirLauncher.exe'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'AirLauncher.exe') -Destination $executable -Force
    Write-Output "Published single-file app: $executable"
    Write-Output 'Copy this EXE to the destination PC. Agent tools and JetBrains sign-in are still required.'
}
finally { Pop-Location }
