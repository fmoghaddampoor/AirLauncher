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

    if ($Action -eq 'login') {
        & rtk proxy central login
        return
    }
    if ($Action -eq 'status') {
        & rtk proxy central status
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
            $null = & rtk proxy central @agentArguments debug prompt-input 'Validate the launcher configuration without sending a model request.' 2> $checkErrorPath
            $checkExitCode = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $previousErrorPreference }
        if ($ReceiptPath) { [IO.File]::WriteAllText($ReceiptPath, [string]$checkExitCode) }
        exit $checkExitCode
    }

    # Interactive agents must inherit the console handles; output proxies turn stdout into a pipe.
    $hasBasicTerminalType = [string]::IsNullOrWhiteSpace($env:TERM) -or $env:TERM -eq 'dumb'
    if ($hasBasicTerminalType) { $env:TERM = 'xterm-256color' }
    $gateway = (Get-Command central.exe -ErrorAction Stop).Source
    $agentProcess = Start-Process -FilePath $gateway -ArgumentList $agentArguments -NoNewWindow -Wait -PassThru
    $agentExitCode = $agentProcess.ExitCode
    if ($agentExitCode -ne 0) {
        Write-Host "Agent exited with code $agentExitCode. Read the error above; use Gateway status in the launcher for connection details." -ForegroundColor Yellow
    }
}
catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($Action -eq 'check') {
        [IO.File]::WriteAllText((Join-Path $AppDirectory 'gateway-check-error.txt'), $_.Exception.Message)
        if ($ReceiptPath) { [IO.File]::WriteAllText($ReceiptPath, '1') }
        exit 1
    }
}
