[CmdletBinding()]
param(
    [Parameter(Mandatory)][Guid]$TenantId,
    [Parameter(Mandatory)][Guid]$SubscriptionId,
    [Parameter(Mandatory)][Guid]$EnvironmentId,
    [Parameter(Mandatory)][Uri]$EnvironmentUrl,
    [ValidateSet('europe', 'switzerland')][string]$ExpectedLocation = 'europe',
    [Parameter(Mandatory)][string]$BaselineSnapshotPath,
    [Parameter(Mandatory)][string]$TargetSecurityPath
)
. "$PSScriptRoot\Dataverse.ps1"
$session = Get-DemoDataverseSession -TenantId $TenantId -SubscriptionId $SubscriptionId `
    -EnvironmentId $EnvironmentId -EnvironmentUrl $EnvironmentUrl -ExpectedName 'Contoso Connector PoC' `
    -ExpectedLocation $ExpectedLocation
$baseline = Get-Content -LiteralPath $BaselineSnapshotPath -Raw | ConvertFrom-Json
$security = Get-Content -LiteralPath $TargetSecurityPath -Raw | ConvertFrom-Json
if ($baseline.environmentId -ne "$EnvironmentId" -or $baseline.connectorApiName -ne $security.apiName) {
    throw 'Baseline must belong to this exact target environment and connector.'
}
$id = $baseline.connectorId
$before = Invoke-Dataverse $session "connectors($id)"
if (-not $before.ismanaged -or $before.connectorinternalid -ne $security.apiName) {
    throw 'Expected the original managed target connector.'
}
$directory = Join-Path $PSScriptRoot '..\out\target-update-preserved'
Invoke-Pac @('connector', 'download', '--environment', $EnvironmentUrl.AbsoluteUri,
    '--connector-id', $id, '--outputDirectory', $directory)
$propertiesPath = Join-Path $directory 'apiProperties.json'
$definitionPath = Join-Path $directory 'apiDefinition.json'
$properties = Get-Content $propertiesPath -Raw | ConvertFrom-Json -Depth 100
$oauth = $properties.properties.connectionParameters.token.oAuthSettings
if ($oauth.clientAssertionType -ne 'GenericFederatedIdentityCredential' -or
    $oauth.properties.FederatedIdentityCredentials.Issuer -ne $security.issuer) {
    throw 'Unexpected OAuth mode or issuer; do not restore by guessing.'
}
$oauth.redirectUrl = $security.redirect
$oauth.properties.FederatedIdentityCredentials.Subject = $security.subject
$json = ConvertTo-Json -InputObject $properties.properties.connectionParameters -Depth 100 -Compress
$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($json)))
if ($hash -ne $baseline.connectionParametersSha256) {
    throw 'Restored full connection-parameter JSON does not exactly match the original target fingerprint.'
}
$properties | ConvertTo-Json -Depth 100 | Set-Content $propertiesPath -Encoding utf8
Invoke-Pac @('connector', 'update', '--environment', $EnvironmentUrl.AbsoluteUri,
    '--connector-id', $id, '--api-definition-file', $definitionPath,
    '--api-properties-file', $propertiesPath)
$after = Invoke-Dataverse $session "connectors($id)"
$actualHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
    [Text.Encoding]::UTF8.GetBytes($after.connectionparameters)))
$sameDefinition = [System.Text.Json.Nodes.JsonNode]::DeepEquals(
    [System.Text.Json.Nodes.JsonNode]::Parse($after.openapidefinition),
    [System.Text.Json.Nodes.JsonNode]::Parse($before.openapidefinition))
if ($actualHash -ne $baseline.connectionParametersSha256 -or
    -not $sameDefinition -or
    $after.policytemplateinstances -ne $before.policytemplateinstances) {
    throw 'Restoration failed to preserve the original target authentication, current definition or header policy.'
}
Write-Output 'Original target OAuth fingerprint restored; effective updated definition and header policy unchanged. Verify federation, binding and real flow execution.'
