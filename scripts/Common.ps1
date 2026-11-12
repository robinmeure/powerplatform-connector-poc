#requires -Version 7.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Az {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = & az @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $operation = @($Arguments | Where-Object { $_ -and $_ -notlike '-*' } | Select-Object -First 2) -join ' '
        throw "Azure CLI command 'az $operation' failed with exit code $exitCode."
    }
    return $output
}

function Invoke-AzJson {
    param([Parameter(Mandatory)][string[]]$Arguments, [switch]$AllowEmpty)
    $output = Invoke-Az -Arguments $Arguments
    if (-not $output) {
        if ($AllowEmpty) { return }
        $operation = @($Arguments | Where-Object { $_ -and $_ -notlike '-*' } | Select-Object -First 2) -join ' '
        throw "Azure CLI command 'az $operation' succeeded without the expected JSON output."
    }
    return ($output -join "`n" | ConvertFrom-Json -Depth 100)
}

function Assert-Tenant {
    param([Parameter(Mandatory)][Guid]$TenantId, [Parameter(Mandatory)][Guid]$SubscriptionId)
    $account = Invoke-AzJson @('account', 'show', '--subscription', "$SubscriptionId", '-o', 'json')
    if ($account.tenantId -ne "$TenantId") { throw 'Azure subscription belongs to a different tenant.' }
}

function Invoke-Graph {
    param([Parameter(Mandatory)][string]$Path, [string]$Method = 'GET', [object]$Body)
    $arguments = @('rest', '--method', $Method, '--url', "https://graph.microsoft.com/v1.0/$Path", '-o', 'json')
    $file = $null
    try {
        if ($null -ne $Body) {
            $directory = Join-Path $PSScriptRoot '..\out'
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $file = Join-Path $directory "$([Guid]::NewGuid()).local.json"
            $Body | ConvertTo-Json -Depth 100 | Set-Content -Path $file -Encoding utf8
            $arguments += @('--body', "@$file", '--headers', 'Content-Type=application/json')
        }
        if ($Method -ieq 'PATCH') {
            return Invoke-AzJson -Arguments $arguments -AllowEmpty
        }
        return Invoke-AzJson -Arguments $arguments
    }
    finally {
        if ($file) { Remove-Item -LiteralPath $file }
    }
}

function Invoke-Pac {
    param([Parameter(Mandatory)][string[]]$Arguments)
    & pac @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $operation = @($Arguments | Where-Object { $_ -and $_ -notlike '-*' } | Select-Object -First 2) -join ' '
        throw "PAC command 'pac $operation' failed with exit code $exitCode."
    }
}
