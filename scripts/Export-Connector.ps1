[CmdletBinding()]
param(
    [string]$IdentityPath = (Join-Path $PSScriptRoot '..\out\identity.local.json'),
    [string]$AzurePath = (Join-Path $PSScriptRoot '..\out\azure.local.json'),
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version = '1.0.0',
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\out\connector')
)
. "$PSScriptRoot\Common.ps1"
$identity = Get-Content -LiteralPath $IdentityPath -Raw | ConvertFrom-Json
$azure = Get-Content -LiteralPath $AzurePath -Raw | ConvertFrom-Json
Assert-Tenant -TenantId $identity.tenantId -SubscriptionId $identity.subscriptionId
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$url = "https://management.azure.com/subscriptions/$($identity.subscriptionId)/resourceGroups/$($azure.resourceGroup)/providers/Microsoft.ApiManagement/service/$($azure.apimName)/apis/cz-proof?format=swagger-json&export=true&api-version=2024-05-01"
$access = Invoke-AzJson @('account', 'get-access-token', '--subscription', $identity.subscriptionId,
    '--resource', 'https://management.azure.com/', '-o', 'json')
$export = Invoke-RestMethod -Uri $url -Headers @{ Authorization = "Bearer $($access.accessToken)" }
$definition = if ($export.value -is [string]) { $export.value | ConvertFrom-Json -Depth 100 } else { $export.value }
if ($null -eq $definition -or $definition.swagger -ne '2.0') {
    throw 'APIM export did not return an inline Swagger 2 definition.'
}
$definition.host = ([Uri]$azure.gatewayUrl).Host
$definition.basePath = '/cz'
$definition.info.version = $Version
$security = @{
    oauth2 = @{
        type = 'oauth2'; flow = 'accessCode'
        authorizationUrl = "https://login.microsoftonline.com/$($identity.tenantId)/oauth2/authorize"
        tokenUrl = "https://login.microsoftonline.com/$($identity.tenantId)/oauth2/token"
        scopes = @{}
    }
}
$definition | Add-Member -NotePropertyName securityDefinitions -NotePropertyValue $security -Force
$definition | Add-Member -NotePropertyName security -NotePropertyValue @(@{ oauth2 = @() }) -Force
$definition | ConvertTo-Json -Depth 100 | Set-Content (Join-Path $OutputDirectory 'apiDefinition.json') -Encoding utf8

$overlay = Get-Content (Join-Path $PSScriptRoot '..\connector\auth-overlay.json') -Raw
$overlay = $overlay.Replace('__TENANT_ID__', $identity.tenantId).
    Replace('__CONNECTOR_ID__', $identity.connectorClientId).
    Replace('__FRONTEND_RESOURCE__', "api://$($identity.frontendClientId)")
$overlay | ConvertFrom-Json -Depth 100 | ConvertTo-Json -Depth 100 |
    Set-Content (Join-Path $OutputDirectory 'apiProperties.json') -Encoding utf8
@{
    connectorId = $null; environment = $null; apiProperties = 'apiProperties.json'
    apiDefinition = 'apiDefinition.json'; icon = $null; script = $null
} | ConvertTo-Json |
    Set-Content (Join-Path $OutputDirectory 'settings.json') -Encoding utf8
Write-Output "APIM definition and separate OAuth/key overlay generated at $OutputDirectory."
Write-Output 'Configure Managed identity on the connector Security tab; download persisted properties before automated updates.'
