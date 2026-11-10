param(
    [Parameter(Mandatory = $true)][string]$Project,
    [ValidateSet('codex', 'claude', 'gemini')][string]$Agent = 'codex',
    [ValidateSet('run', 'login', 'status', 'check')][string]$Action = 'run',
    [Parameter(Mandatory = $true)][string]$AppDirectory,
    [string]$ReceiptPath,
    [string]$CodexModel = 'gpt-6.1-sol',
    [ValidateSet('low', 'medium', 'high', 'xhigh', 'max', 'ultra')][string]$CodexReasoningEffort = 'medium',
    [ValidateSet('full-access', 'workspace-write', 'read-only')][string]$CodexPermissions = 'full-access'
)

$ErrorActionPreference = 'Stop'
try {
    Set-Location -LiteralPath $Project
    $Host.UI.RawUI.WindowTitle = 'Air / ' + $Agent
    Write-Host ''
    Write-Host '  AIR / JetBrains AI' -ForegroundColor Cyan
    Write-Host "  $Project" -ForegroundColor DarkGray
    Write-Host ''

    # Refresh PATH from registry and ensure standard CLI directories are present even when launched from stale environments.
    $pathParts = @()
    if ($env:PATH) { $pathParts += ($env:PATH -split [IO.Path]::PathSeparator) }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath) { $pathParts += ($userPath -split [IO.Path]::PathSeparator) }
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($machinePath) { $pathParts += ($machinePath -split [IO.Path]::PathSeparator) }

    $standardDirs = @(
        (Join-Path $env:USERPROFILE '.local\bin'),
        (Join-Path $env:USERPROFILE '.cargo\bin'),
        (Join-Path $env:USERPROFILE '.rtk\bin'),
        (Join-Path $env:USERPROFILE '.headroom\bin'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'),
        (Join-Path $env:LOCALAPPDATA 'Programs\central')
    )
    foreach ($dir in $standardDirs) {
        if ([IO.Directory]::Exists($dir)) {
            $pathParts += $dir
        }
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $uniquePaths = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $pathParts) {
        $clean = $entry.Trim()
        if ($clean -and $seen.Add($clean)) {
            $uniquePaths.Add($clean)
        }
    }
    $env:PATH = ($uniquePaths -join [IO.Path]::PathSeparator)

    # Locate the JetBrains Central CLI gateway executable.
    $gatewayCmd = Get-Command central.exe -ErrorAction SilentlyContinue
    if (-not $gatewayCmd) {
        $gatewayCmd = Get-Command central -ErrorAction SilentlyContinue
    }
    if (-not $gatewayCmd) {
        $candidatePaths = @(
            (Join-Path $env:USERPROFILE '.local\bin\central.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\central\central.exe'),
            (Join-Path $env:ProgramFiles 'JetBrains\Central\central.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'JetBrains\Central\central.exe')
        )
        foreach ($candidate in $candidatePaths) {
            if ([IO.File]::Exists($candidate)) {
                $candidateDir = [IO.Path]::GetDirectoryName($candidate)
                $env:PATH = $candidateDir + [IO.Path]::PathSeparator + $env:PATH
                $gatewayCmd = [pscustomobject]@{ Source = $candidate }
                break
            }
        }
    }
    if (-not $gatewayCmd) {
        throw "JetBrains Central CLI ('central.exe') was not found in PATH or at '$env:USERPROFILE\.local\bin\central.exe'. Install Central CLI (https://www.jetbrains.com/help/central-cli/quickstart.html)."
    }
    $gateway = $gatewayCmd.Source

    function Stop-StaleGatewayProxy {
        param([int]$Port = 19516)
        try {
            $connections = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
            foreach ($conn in $connections) {
                $procId = $conn.OwningProcess
                if ($procId -and $procId -ne $PID) {
                    $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
                    if ($proc -and ($proc.ProcessName -like '*central*' -or $proc.Path -like '*central.exe*')) {
                        $activeAgent = Get-CimInstance Win32_Process -Filter "Name = 'central.exe'" -ErrorAction SilentlyContinue |
                            Where-Object { $_.CommandLine -like '*run *' -and $_.ProcessId -ne $PID -and $_.ProcessId -ne $procId }
                        if (-not $activeAgent) {
                            Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            }
            $runningCentral = Get-Process -Name 'central' -ErrorAction SilentlyContinue
            if (-not $runningCentral) {
                $pidFile = Join-Path $env:USERPROFILE '.jetbrains-central\proxy.pid'
                if ([IO.File]::Exists($pidFile)) {
                    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
                }
            }
        }
        catch { }
    }

    # Ensure stale or orphaned proxy daemons do not block port 19516.
    Stop-StaleGatewayProxy

    if ($Action -eq 'login') {
        if (Get-Command rtk.exe -ErrorAction SilentlyContinue) {
            & rtk proxy central login
        } else {
            & $gateway login
        }
        return
    }
    if ($Action -eq 'status') {
        if (Get-Command rtk.exe -ErrorAction SilentlyContinue) {
            & rtk proxy central status
        } else {
            & $gateway status
        }
        return
    }

    $agentArguments = @('run', $Agent)
    if ($Agent -eq 'codex') {
        # Start-Process joins ArgumentList into a command line. Only accept model ID characters.
        if ($CodexModel -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.:/-]*$') {
            throw 'Enter a valid Codex model ID (no spaces).'
        }
        $agentArguments += @('--', '--model', $CodexModel, '-c', "model_reasoning_effort=$CodexReasoningEffort")
        if ($CodexPermissions -eq 'full-access') {
            $agentArguments += '--dangerously-bypass-approvals-and-sandbox'
        }
        else {
            $agentArguments += @('--sandbox', $CodexPermissions, '--ask-for-approval', 'on-request')
        }
        $env:CODEX_HOME = Join-Path $AppDirectory 'codex'
        $null = New-Item -ItemType Directory -Path $env:CODEX_HOME -Force
        $toolDirectory = Join-Path $AppDirectory 'tools\node_modules\.bin'
        $localCodex = Join-Path $toolDirectory 'codex.cmd'
        if (-not ([IO.File]::Exists($localCodex))) {
            throw "The launcher Codex installation is missing at '$localCodex'. Run Build.ps1 to install it."
        }
        $env:PATH = $toolDirectory + [IO.Path]::PathSeparator + $env:PATH
    }

    if ($Action -eq 'check') {
        if ([Console]::IsOutputRedirected) { throw 'PowerShell stdout is redirected instead of attached to Windows Terminal.' }

        $checkErrorPath = Join-Path $AppDirectory 'gateway-check-error.txt'
        $previousErrorPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            if (Get-Command rtk.exe -ErrorAction SilentlyContinue) {
                $null = & rtk proxy central @agentArguments debug prompt-input 'Validate the launcher configuration without sending a model request.' 2> $checkErrorPath
            } else {
                $null = & $gateway @agentArguments debug prompt-input 'Validate the launcher configuration without sending a model request.' 2> $checkErrorPath
            }
            $checkExitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorPreference
            Stop-StaleGatewayProxy
        }
        if ($ReceiptPath) { [IO.File]::WriteAllText($ReceiptPath, [string]$checkExitCode) }
        exit $checkExitCode
    }

    # Interactive agents must inherit the console handles; output proxies turn stdout into a pipe.
    $hasBasicTerminalType = [string]::IsNullOrWhiteSpace($env:TERM) -or $env:TERM -eq 'dumb'
    if ($hasBasicTerminalType) { $env:TERM = 'xterm-256color' }
    $agentProcess = Start-Process -FilePath $gateway -ArgumentList $agentArguments -NoNewWindow -Wait -PassThru
    $agentExitCode = $agentProcess.ExitCode
    if ($agentExitCode -ne 0) {
        Write-Host "Agent exited with code $agentExitCode. Read the error above; use Gateway status in the launcher for connection details." -ForegroundColor Yellow
    }
    Stop-StaleGatewayProxy
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($Action -eq 'check') {
        [IO.File]::WriteAllText((Join-Path $AppDirectory 'gateway-check-error.txt'), $_.Exception.Message)
        if ($ReceiptPath) { [IO.File]::WriteAllText($ReceiptPath, '1') }
        exit 1
    }
}
