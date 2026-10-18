$ErrorActionPreference = 'Stop'
$appDirectory = Join-Path $env:USERPROFILE '.air-launcher'
$receiptPath = Join-Path $appDirectory ('terminal-manual-' + [Guid]::NewGuid().ToString('N') + '.txt')
$payload = @{
    project = $PSScriptRoot
    agent = 'codex'
    action = 'check'
    app_directory = $appDirectory
    receipt = $receiptPath
} | ConvertTo-Json -Compress
$payloadBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
$source = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'src\terminal.ps1'))
$bootstrap = @'
$json = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD__'))
$launch = $json | ConvertFrom-Json
$parameters = @{ Project=$launch.project; Agent=$launch.agent; Action=$launch.action; AppDirectory=$launch.app_directory; ReceiptPath=$launch.receipt }
& {
__SOURCE__
} @parameters
'@
$bootstrap = $bootstrap.Replace('__PAYLOAD__', $payloadBase64).Replace('__SOURCE__', $source)
$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($bootstrap))
Start-Process -FilePath wt.exe -ArgumentList @('-w', 'new', 'new-tab', 'powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand) | Out-Null
$deadline = [DateTime]::UtcNow.AddSeconds(45)
while ([DateTime]::UtcNow -lt $deadline) {
    if (Test-Path -LiteralPath $receiptPath) {
        $receipt = [IO.File]::ReadAllText($receiptPath).Trim()
        if ($receipt -eq '0') { Write-Output 'PASS: encoded Windows Terminal startup and gateway configuration.'; exit 0 }
        Get-Content -LiteralPath (Join-Path $appDirectory 'gateway-check-error.txt')
        exit 1
    }
    Start-Sleep -Milliseconds 200
}
throw 'Windows Terminal did not return a receipt.'
