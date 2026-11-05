[CmdletBinding()]
param(
    [Parameter(Mandatory)][Guid]$TenantId,
    [Parameter(Mandatory)][Guid]$SubscriptionId,
    [Parameter(Mandatory)][Guid]$EnvironmentId,
    [Parameter(Mandatory)][Uri]$EnvironmentUrl,
    [ValidateSet('europe', 'switzerland')][string]$ExpectedLocation = 'europe',
    [Parameter(Mandatory)][Guid]$ConnectorId,
    [Parameter(Mandatory)][string]$ApiDefinitionPath,
    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')][string]$SolutionVersion = '1.0.1.0'
)
. "$PSScriptRoot\Dataverse.ps1"
. "$PSScriptRoot\ConnectorSecurity.ps1"
$session = New-DemoDataverseSession -TenantId $TenantId -SubscriptionId $SubscriptionId `
    -EnvironmentId $EnvironmentId -EnvironmentUrl $EnvironmentUrl -ExpectedName 'CZ Connector PoC Build' `
    -ExpectedLocation $ExpectedLocation
$before = Invoke-Dataverse $session "connectors($ConnectorId)"
if ($before.displayname -ne 'CZ Connector Proof' -or $before.ismanaged) {
    throw 'Definition updates are allowed only on the unmanaged demo authoring connector.'
}
$oldDefinition = $before.openapidefinition | ConvertFrom-Json -Depth 100
$newDefinition = Get-Content -LiteralPath $ApiDefinitionPath -Raw | ConvertFrom-Json -Depth 100
$oldOperation = $oldDefinition.paths.'/proof'.get
$newOperation = $newDefinition.paths.'/proof'.get
if ($oldOperation.operationId -ne $newOperation.operationId -or
    $oldDefinition.host -ne $newDefinition.host -or
    $oldDefinition.basePath -ne $newDefinition.basePath) {
    throw 'This proof requires a compatible update with stable host, base path and operation ID.'
}
$directory = Join-Path $PSScriptRoot '..\out\update-preserved'
Invoke-Pac @('connector', 'download', '--environment', $EnvironmentUrl.AbsoluteUri,
    '--connector-id', "$ConnectorId", '--outputDirectory', $directory)
$propertiesPath = Join-Path $directory 'apiProperties.json'
$properties = Get-Content $propertiesPath -Raw | ConvertFrom-Json
if ($properties.properties.connectionParameters.api_key.type -ne 'securestring' -or
    $properties.properties.connectionParameters.token.oAuthSettings.clientAssertionType -ne 'GenericFederatedIdentityCredential' -or
    @($properties.properties.policyTemplateInstances).Count -ne 1) {
    throw 'Persisted Managed identity, key parameter and request policy must be present before updating.'
}
# PAC clears policy templates when the properties file is omitted.
Invoke-Pac @('connector', 'update', '--environment', $EnvironmentUrl.AbsoluteUri,
    '--connector-id', "$ConnectorId", '--api-definition-file', $ApiDefinitionPath,
    '--api-properties-file', $propertiesPath)
$after = Invoke-Dataverse $session "connectors($ConnectorId)"
Assert-ConnectorSecurityUnchanged -Before $before -After $after
$solutions = Invoke-Dataverse $session "solutions?`$filter=uniquename eq 'CZPoCConnector'"
if ($solutions.value.Count -ne 1) { throw 'Expected exactly one connector authoring solution.' }
Invoke-Dataverse $session "solutions($($solutions.value[0].solutionid))" PATCH @{ version = $SolutionVersion } | Out-Null
$fingerprint = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
    [Text.Encoding]::UTF8.GetBytes([string]$after.connectionparameters)))
@{
    connectorId = "$ConnectorId"; solutionVersion = $SolutionVersion
    securityMetadataUnchanged = $true; connectionParametersSha256 = $fingerprint
    note = 'Authoring definition update with unchanged downloaded properties; managed target import and real flow rerun remain required.'
} | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot '..\out\definition-update.local.json') -Encoding utf8
Write-Output 'Definition updated without overwriting authentication metadata. Export/import the managed connector and rerun the original target flow.'
