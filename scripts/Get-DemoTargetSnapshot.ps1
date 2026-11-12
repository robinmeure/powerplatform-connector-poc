[CmdletBinding()]
param(
    [Parameter(Mandatory)][Guid]$TenantId,
    [Parameter(Mandatory)][Guid]$SubscriptionId,
    [Parameter(Mandatory)][Guid]$EnvironmentId,
    [Parameter(Mandatory)][Uri]$EnvironmentUrl,
    [Parameter(Mandatory)][string]$OutputPath,
    [ValidateSet('europe', 'switzerland')][string]$ExpectedLocation = 'europe'
)
. "$PSScriptRoot\Dataverse.ps1"
$session = Get-DemoDataverseSession -TenantId $TenantId -SubscriptionId $SubscriptionId `
    -EnvironmentId $EnvironmentId -EnvironmentUrl $EnvironmentUrl -ExpectedName 'Contoso Connector PoC' `
    -ExpectedLocation $ExpectedLocation
$connectors = Invoke-Dataverse $session "connectors?`$filter=displayname eq 'Contoso Connector Proof'"
$references = Invoke-Dataverse $session "connectionreferences?`$filter=connectionreferencelogicalname eq 'contoso_ContosoProofConnection'"
$flows = Invoke-Dataverse $session "workflows?`$filter=name eq 'Contoso Identity Boundary Proof' and category eq 5"
$solutions = Invoke-Dataverse $session "solutions?`$filter=uniquename eq 'ContosoPoCConnector'"
$consumerSolutions = Invoke-Dataverse $session "solutions?`$filter=uniquename eq 'ContosoPoCConsumer'"
if ($connectors.value.Count -ne 1 -or $references.value.Count -ne 1 -or
    $flows.value.Count -ne 1 -or $solutions.value.Count -ne 1 -or $consumerSolutions.value.Count -ne 1) {
    throw 'Expected exactly one managed demo connector, reference, flow and connector solution.'
}
$connector = $connectors.value[0]
$reference = $references.value[0]
$flow = $flows.value[0]
if (-not $connector.ismanaged -or -not $reference.ismanaged -or -not $flow.ismanaged -or
    [string]::IsNullOrWhiteSpace($reference.connectionid)) {
    throw 'Expected managed components with an existing target Connection binding.'
}
function Get-Fingerprint([string]$Value) {
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Value)))
}
$parameters = $connector.connectionparameters | ConvertFrom-Json
$normalizedPolicies = @($connector.policytemplateinstances | ConvertFrom-Json | ForEach-Object {
    $unknown = @($_.PSObject.Properties.Name | Where-Object { $_ -notin @('templateId', 'title', 'parameters') })
    if ($unknown.Count) { throw 'Unexpected policy wrapper fields; inspect before normalizing.' }
    [ordered]@{ templateId = $_.templateId; title = $_.title; parameters = $_.parameters }
})
$policyJson = ConvertTo-Json -InputObject $normalizedPolicies -Depth 100 -Compress
if ($parameters.api_key.type -ne 'securestring' -or
    $parameters.token.oAuthSettings.clientAssertionType -ne 'GenericFederatedIdentityCredential') {
    throw 'Required secure key parameter or Managed identity authentication is missing.'
}
@{
    capturedAt = (Get-Date).ToUniversalTime().ToString('o')
    environmentId = "$EnvironmentId"
    connectorId = $connector.connectorid
    connectorApiName = $connector.connectorinternalid
    connectorSolutionVersion = $solutions.value[0].version
    consumerSolutionVersion = $consumerSolutions.value[0].version
    definitionVersion = ($connector.openapidefinition | ConvertFrom-Json).info.version
    connectionReferenceId = $reference.connectionreferenceid
    connectionReferenceLogicalName = $reference.connectionreferencelogicalname
    connectionId = $reference.connectionid
    referenceConnectorId = $reference.connectorid
    workflowId = $flow.workflowid
    flowState = $flow.statecode
    connectionParametersSha256 = Get-Fingerprint $connector.connectionparameters
    connectionParameterSetsSha256 = Get-Fingerprint ([string]$connector.connectionparametersets)
    policyTemplateInstancesSha256 = Get-Fingerprint ([string]$connector.policytemplateinstances)
    policyTemplateInstancesNormalizedSha256 = Get-Fingerprint $policyJson
    definitionSha256 = Get-Fingerprint $connector.openapidefinition
    note = 'Metadata and hashes only; no Connection credential values are queried or recorded.'
} | ConvertTo-Json | Set-Content -LiteralPath $OutputPath -Encoding utf8
Write-Output "Managed target metadata snapshot saved to $OutputPath."
