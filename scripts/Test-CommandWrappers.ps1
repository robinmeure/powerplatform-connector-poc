$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

$script:AzExitCode = 0
$script:AzOutput = $null
$script:PacExitCode = 0
function az {
    $global:LASTEXITCODE = $script:AzExitCode
    if ($null -ne $script:AzOutput) { $script:AzOutput }
}
function pac { $global:LASTEXITCODE = $script:PacExitCode }

function Assert-ThrowsError {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$ExpectedMessage)
    $caught = $false
    try { & $Action }
    catch {
        if ($_.Exception.Message -ne $ExpectedMessage) { throw }
        $caught = $true
    }
    if (-not $caught) { throw "Expected exception: $ExpectedMessage" }
}

$script:AzExitCode = 17
Assert-ThrowsError {
    Invoke-Az @('deployment', 'sub', 'create', '--parameters', 'sensitive-value')
} "Azure CLI command 'az deployment sub' failed with exit code 17."

$script:AzExitCode = 0
$script:AzOutput = '{"tenantId":"tenant"}'
$account = Invoke-AzJson @('account', 'show', '-o', 'json')
if ($account.tenantId -ne 'tenant') { throw 'Azure CLI JSON output was not parsed.' }

$script:AzOutput = $null
Assert-ThrowsError {
    Invoke-AzJson @('account', 'show', '-o', 'json')
} "Azure CLI command 'az account show' succeeded without the expected JSON output."

$patchResult = Invoke-Graph -Path 'applications/test' -Method PATCH
if ($null -ne $patchResult) { throw 'Empty successful Graph PATCH response should return no object.' }
Assert-ThrowsError {
    Invoke-Graph -Path 'applications/test'
} "Azure CLI command 'az rest GET' succeeded without the expected JSON output."

$script:PacExitCode = 29
Assert-ThrowsError {
    Invoke-Pac @('solution', 'export', '--path', 'sensitive-value')
} "PAC command 'pac solution export' failed with exit code 29."

$global:LASTEXITCODE = 0
Write-Output 'PASS: CLI failures include operation and exit code without echoing argument values.'
