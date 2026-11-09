[CmdletBinding()]
param(
    [Parameter(Mandatory)][Guid]$TenantId,
    [Parameter(Mandatory)][Guid]$SubscriptionId,
    [Parameter(Mandatory)][Guid]$EnvironmentId,
    [Parameter(Mandatory)][Uri]$EnvironmentUrl,
    [Parameter(Mandatory)][Guid]$ConnectorId,
    [ValidateSet('europe', 'switzerland')][string]$ExpectedLocation = 'europe'
)
. "$PSScriptRoot\Dataverse.ps1"
$session = New-DemoDataverseSession -TenantId $TenantId -SubscriptionId $SubscriptionId `
    -EnvironmentId $EnvironmentId -EnvironmentUrl $EnvironmentUrl -ExpectedName 'Contoso Connector PoC Build' `
    -ExpectedLocation $ExpectedLocation
$before = Invoke-Dataverse $session "connectors($ConnectorId)"
if ($before.displayname -ne 'Contoso Connector Proof' -or $before.ismanaged) {
    throw 'Only the unmanaged demo authoring connector may be changed.'
}
$directory = Join-Path $PSScriptRoot '..\out\connector-persisted'
Invoke-Pac @('connector', 'download', '--environment', $EnvironmentUrl.AbsoluteUri,
    '--connector-id', "$ConnectorId", '--outputDirectory', $directory)
$path = Join-Path $directory 'apiProperties.json'
$properties = Get-Content $path -Raw | ConvertFrom-Json -AsHashtable
$oauth = $properties.properties.connectionParameters.token.oAuthSettings
if ($oauth.clientAssertionType -ne 'GenericFederatedIdentityCredential') {
    throw 'Configure and save Managed identity in the Security UI first.'
}
$beforeOAuth = $oauth | ConvertTo-Json -Depth 100 -Compress
$overlay = Get-Content (Join-Path $PSScriptRoot '..\connector\auth-overlay.json') -Raw | ConvertFrom-Json -AsHashtable
$properties.properties.connectionParameters.api_key = $overlay.properties.connectionParameters.api_key
$properties | ConvertTo-Json -Depth 100 | Set-Content $path -Encoding utf8
Invoke-Pac @('connector', 'update', '--environment', $EnvironmentUrl.AbsoluteUri,
    '--connector-id', "$ConnectorId", '--api-definition-file', (Join-Path $directory 'apiDefinition.json'),
    '--api-properties-file', $path)
$after = Invoke-Dataverse $session "connectors($ConnectorId)"
$parameters = $after.connectionparameters | ConvertFrom-Json -AsHashtable
if (-not $parameters.ContainsKey('api_key') -or $parameters.api_key.type -ne 'securestring') {
    throw 'Subscription-key parameter was not persisted.'
}
$afterOAuth = $parameters.token.oAuthSettings | ConvertTo-Json -Depth 100 -Compress
if ($beforeOAuth -ne $afterOAuth) {
    throw 'OAuth metadata changed while restoring the subscription parameter. Inspect before exporting.'
}
Write-Output 'Required subscription-key parameter restored; persisted Managed identity OAuth metadata is unchanged.'
