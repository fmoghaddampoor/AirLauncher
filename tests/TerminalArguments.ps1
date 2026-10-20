$ErrorActionPreference = 'Stop'
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('air-launcher-arguments-' + [Guid]::NewGuid().ToString('N'))
$originalPath = $env:PATH
$originalCodexHome = $env:CODEX_HOME
$originalTerm = $env:TERM
$originalTitle = $Host.UI.RawUI.WindowTitle
$originalDirectory = Get-Location
$capture = @{ Arguments = $null }

# Capture the real script's native process boundary without launching an agent or model request.
function Get-Command { [pscustomobject]@{ Source = 'central.exe' } }
function Start-Process {
    param($FilePath, $ArgumentList, [switch]$NoNewWindow, [switch]$Wait, [switch]$PassThru)
    if ($FilePath -ne 'central.exe' -or -not $NoNewWindow) { throw 'Interactive console handles must be inherited.' }
    $capture.Arguments = $ArgumentList
    [pscustomobject]@{ ExitCode = 0 }
}

try {
    $toolDirectory = Join-Path $testDirectory 'tools\node_modules\.bin'
    $null = New-Item -ItemType Directory -Path $toolDirectory -Force
    [IO.File]::WriteAllText((Join-Path $toolDirectory 'codex.cmd'), '')
    $terminalScript = Join-Path $PSScriptRoot '..\src\terminal.ps1'
    foreach ($mode in @('full-access', 'workspace-write', 'read-only')) {
        $capture.Arguments = $null
        & $terminalScript -Project $testDirectory -AppDirectory $testDirectory -CodexModel 'gpt-6.1-sol' -CodexReasoningEffort 'medium' -CodexPermissions $mode
        $expected = @('run', 'codex', '--', '--model', 'gpt-6.1-sol', '-c', 'model_reasoning_effort=medium')
        if ($mode -eq 'full-access') { $expected += '--dangerously-bypass-approvals-and-sandbox' }
        else { $expected += @('--sandbox', $mode, '--ask-for-approval', 'on-request') }
        if (($capture.Arguments -join '|') -cne ($expected -join '|')) {
            throw "Incorrect $mode arguments: $($capture.Arguments)"
        }
    }
    & $terminalScript -Project $testDirectory -AppDirectory $testDirectory -CodexModel 'custom-model' -CodexReasoningEffort 'high' -CodexPermissions 'read-only'
    if (($capture.Arguments -join '|') -cne 'run|codex|--|--model|custom-model|-c|model_reasoning_effort=high|--sandbox|read-only|--ask-for-approval|on-request') {
        throw 'Custom model or reasoning selection was lost.'
    }
    foreach ($agent in @('claude', 'gemini')) {
        & $terminalScript -Project $testDirectory -AppDirectory $testDirectory -Agent $agent
        if (($capture.Arguments -join '|') -ne "run|$agent") { throw 'Codex settings leaked into another agent.' }
    }
    foreach ($invalidModel in @('model --search', 'model"', 'model;whoami', '--search')) {
        $capture.Arguments = $null
        & $terminalScript -Project $testDirectory -AppDirectory $testDirectory -CodexModel $invalidModel
        if ($null -ne $capture.Arguments) { throw 'Invalid model reached the native process.' }
    }
    Write-Output 'PASS: all Codex permission modes, other agents, and model argument validation.'
}
finally {
    Set-Location -LiteralPath $originalDirectory.Path
    $env:PATH = $originalPath
    $env:CODEX_HOME = $originalCodexHome
    $env:TERM = $originalTerm
    $Host.UI.RawUI.WindowTitle = $originalTitle
    # Delete only the unique temporary directory created by this test.
    $resolvedTestDirectory = [IO.Path]::GetFullPath($testDirectory)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolvedTestDirectory.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected test directory.' }
    Remove-Item -LiteralPath $resolvedTestDirectory -Recurse -Force
}
