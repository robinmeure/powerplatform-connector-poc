[CmdletBinding()]
param(
    [string]$IdentityPath = (Join-Path $PSScriptRoot '..\out\identity.local.json'),
    [string]$AzurePath = (Join-Path $PSScriptRoot '..\out\azure.local.json'),
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\out\boundary-evidence.local.json')
)
. "$PSScriptRoot\Common.ps1"
$identity = Get-Content -LiteralPath $IdentityPath -Raw | ConvertFrom-Json
$azure = Get-Content -LiteralPath $AzurePath -Raw | ConvertFrom-Json
Assert-Tenant -TenantId $identity.tenantId -SubscriptionId $identity.subscriptionId
$subscription = "https://management.azure.com/subscriptions/$($identity.subscriptionId)/resourceGroups/$($azure.resourceGroup)/providers/Microsoft.ApiManagement/service/$($azure.apimName)/subscriptions/contoso-demo-connection/listSecrets?api-version=2024-05-01"
$keys = Invoke-AzJson @('rest', '--method', 'post', '--url', $subscription, '-o', 'json')
$armToken = Invoke-AzJson @('account', 'get-access-token', '--subscription', $identity.subscriptionId,
    '--resource', 'https://management.azure.com/', '-o', 'json')
$cases = @(
    @{ name = 'missing-subscription'; url = "$($azure.gatewayUrl)/contoso/proof"; headers = @{}; expected = 401 },
    @{ name = 'invalid-subscription'; url = "$($azure.gatewayUrl)/contoso/proof"; headers = @{ 'Ocp-Apim-Subscription-Key' = 'deliberately-invalid' }; expected = 401 },
    @{ name = 'missing-delegated-token'; url = "$($azure.gatewayUrl)/contoso/proof"; headers = @{ 'Ocp-Apim-Subscription-Key' = $keys.primaryKey }; expected = 401 },
    @{ name = 'malformed-token'; url = "$($azure.gatewayUrl)/contoso/proof"; headers = @{ 'Ocp-Apim-Subscription-Key' = $keys.primaryKey; Authorization = 'Bearer deliberately-invalid' }; expected = 401 },
    @{ name = 'real-token-wrong-audience'; url = "$($azure.gatewayUrl)/contoso/proof"; headers = @{ 'Ocp-Apim-Subscription-Key' = $keys.primaryKey; Authorization = "Bearer $($armToken.accessToken)" }; expected = 401 },
    @{ name = 'direct-backend-anonymous'; url = "$($azure.backendUrl)/proof"; headers = @{}; expected = 401 }
)
$results = foreach ($case in $cases) {
    $response = Invoke-WebRequest -Uri $case.url -Headers $case.headers -SkipHttpErrorCheck
    @{
        name = $case.name; expected = $case.expected; observed = [int]$response.StatusCode
        passed = [int]$response.StatusCode -eq $case.expected
    }
}
@{
    capturedAt = (Get-Date).ToUniversalTime().ToString('o')
    gatewayUrl = $azure.gatewayUrl; backendUrl = $azure.backendUrl
    cases = @($results)
    note = 'No tokens, keys, response headers or connection credentials are recorded. Missing role/client/scope cases require separate authorized identities; unit tests are not live proof.'
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8
$failed = @($results | Where-Object { -not $_.passed })
if ($failed.Count) { throw "Live authorization checks failed: $($failed.name -join ', '). See redacted evidence." }
Write-Output "All $($results.Count) live rejection cases passed. Redacted evidence: $OutputPath."
