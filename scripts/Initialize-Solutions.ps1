[CmdletBinding()]
param(
    [Parameter(Mandatory)][Guid]$TenantId,
    [Parameter(Mandatory)][Guid]$SubscriptionId,
    [Parameter(Mandatory)][Guid]$EnvironmentId,
    [Parameter(Mandatory)][Uri]$EnvironmentUrl,
    [ValidateSet('europe', 'switzerland')][string]$ExpectedLocation = 'europe',
    [string]$ConnectorDirectory = (Join-Path $PSScriptRoot '..\out\connector')
)
. "$PSScriptRoot\Dataverse.ps1"
$session = New-DemoDataverseSession -TenantId $TenantId -SubscriptionId $SubscriptionId `
    -EnvironmentId $EnvironmentId -EnvironmentUrl $EnvironmentUrl -ExpectedName 'Contoso Connector PoC Build' `
    -ExpectedLocation $ExpectedLocation
$publisher = Invoke-Dataverse $session "publishers?`$filter=uniquename eq 'contosopocpublisher'"
if ($publisher.value.Count -gt 1) { throw 'Ambiguous demo publisher.' }
if ($publisher.value.Count -eq 0) {
    $publisherRecord = Invoke-Dataverse $session 'publishers' POST @{
        uniquename = 'contosopocpublisher'; friendlyname = 'Contoso Connector PoC'
        customizationprefix = 'contoso'; customizationoptionvalueprefix = 73510
    }
}
else { $publisherRecord = $publisher.value[0] }

foreach ($name in @('ContosoPoCConnector', 'ContosoPoCConsumer')) {
    $solutions = Invoke-Dataverse $session "solutions?`$filter=uniquename eq '$name'"
    if ($solutions.value.Count -eq 0) {
        Invoke-Dataverse $session 'solutions' POST @{
            uniquename = $name; friendlyname = $name; version = '1.0.0.0'
            description = 'Isolated Contoso custom connector proof of concept.'
            'publisherid@odata.bind' = "/publishers($($publisherRecord.publisherid))"
        } | Out-Null
    }
    elseif ($solutions.value.Count -ne 1 -or $solutions.value[0].ismanaged -or
        $solutions.value[0]._publisherid_value -ne $publisherRecord.publisherid) {
        throw "Existing solution $name is not the expected authoring solution."
    }
}
$connectors = Invoke-Dataverse $session "connectors?`$filter=displayname eq 'Contoso Connector Proof'"
if ($connectors.value.Count -gt 1) { throw 'Ambiguous connector display name.' }
if ($connectors.value.Count -eq 0) {
    Invoke-Pac @('connector', 'create', '--environment', $EnvironmentUrl.AbsoluteUri,
        '--api-definition-file', (Join-Path $ConnectorDirectory 'apiDefinition.json'),
        '--api-properties-file', (Join-Path $ConnectorDirectory 'apiProperties.json'),
        '--solution-unique-name', 'ContosoPoCConnector')
    $connectors = Invoke-Dataverse $session "connectors?`$filter=displayname eq 'Contoso Connector Proof'"
}
if ($connectors.value.Count -ne 1) { throw 'Connector creation has not produced exactly one Dataverse connector.' }
$record = $connectors.value[0]
@{
    environmentId = "$EnvironmentId"; environmentUrl = $EnvironmentUrl.AbsoluteUri
    connectorId = $record.connectorid; connectorName = $record.name
    connectorInternalId = $record.connectorinternalid
    connectorSolution = 'ContosoPoCConnector'; consumerSolution = 'ContosoPoCConsumer'
} | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot '..\out\authoring.local.json') -Encoding utf8
Write-Output 'Authoring solutions and connector are ready. Configure connector Managed identity and its federation before exporting managed solutions.'
