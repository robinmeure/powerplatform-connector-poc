[CmdletBinding()]
param(
    [Parameter(Mandatory)][Guid]$TenantId,
    [Parameter(Mandatory)][Guid]$SubscriptionId,
    [Parameter(Mandatory)][Guid]$EnvironmentId,
    [Parameter(Mandatory)][Uri]$EnvironmentUrl,
    [ValidateSet('europe', 'switzerland')][string]$ExpectedLocation = 'europe',
    [Parameter(Mandatory)][ValidatePattern('^shared_[A-Za-z0-9_-]+$')][string]$ApiName
)
. "$PSScriptRoot\Dataverse.ps1"
$session = Get-DemoDataverseSession -TenantId $TenantId -SubscriptionId $SubscriptionId `
    -EnvironmentId $EnvironmentId -EnvironmentUrl $EnvironmentUrl -ExpectedName 'Contoso Connector PoC Build' `
    -ExpectedLocation $ExpectedLocation
$connectors = Invoke-Dataverse $session "connectors?`$filter=connectorinternalid eq '$ApiName'"
if ($connectors.value.Count -ne 1 -or $connectors.value[0].displayname -ne 'Contoso Connector Proof' -or
    $connectors.value[0].ismanaged) {
    throw 'API name must resolve to the unmanaged demo authoring connector.'
}
$connector = $connectors.value[0]
$reference = Invoke-Dataverse $session "connectionreferences?`$filter=connectionreferencelogicalname eq 'contoso_ContosoProofConnection'"
if ($reference.value.Count -gt 1) { throw 'Ambiguous connection reference.' }
if ($reference.value.Count -eq 0) {
    $record = Invoke-Dataverse $session 'connectionreferences' POST @{
        connectionreferencelogicalname = 'contoso_ContosoProofConnection'
        connectionreferencedisplayname = 'Contoso Proof Connection'
        connectorid = "/providers/Microsoft.PowerApps/apis/$ApiName"
        'CustomConnectorId@odata.bind' = "/connectors($($connector.connectorid))"
    }
}
else {
    $record = $reference.value[0]
    if ($record.connectorid -ne "/providers/Microsoft.PowerApps/apis/$ApiName" -or
        $record._customconnectorid_value -ne $connector.connectorid) {
        throw 'Existing connection reference points to a different connector.'
    }
}
Invoke-Pac @('solution', 'add-solution-component', '--environment', $EnvironmentUrl.AbsoluteUri,
    '--solutionUniqueName', 'ContosoPoCConsumer', '--component', $record.connectionreferenceid,
    '--componentType', 'connectionreference', '--AddRequiredComponents', 'false')
$flow = Invoke-Dataverse $session "workflows?`$filter=name eq 'Contoso Identity Boundary Proof' and category eq 5"
if ($flow.value.Count -gt 1) { throw 'Ambiguous consumer flow.' }
if ($flow.value.Count -eq 0) {
    $definition = (Get-Content (Join-Path $PSScriptRoot '..\consumer\flowDefinition.json') -Raw).
        Replace('__API_NAME__', $ApiName)
    $flowRecord = Invoke-Dataverse $session 'workflows' POST @{
        category = 5; name = 'Contoso Identity Boundary Proof'; type = 1; primaryentity = 'none'
        description = 'Calls the custom connector through an environment-local Connection Reference.'
        clientdata = $definition
    }
}
else {
    $flowRecord = $flow.value[0]
    if ($flowRecord.ismanaged) { throw 'Consumer authoring flow must be unmanaged.' }
}
Invoke-Pac @('solution', 'add-solution-component', '--environment', $EnvironmentUrl.AbsoluteUri,
    '--solutionUniqueName', 'ContosoPoCConsumer', '--component', $flowRecord.workflowid,
    '--componentType', '29', '--AddRequiredComponents', 'false')
$central = Invoke-Dataverse $session "solutions?`$filter=uniquename eq 'ContosoPoCConnector'"
$consumer = Invoke-Dataverse $session "solutions?`$filter=uniquename eq 'ContosoPoCConsumer'"
if ($central.value.Count -ne 1 -or $consumer.value.Count -ne 1) {
    throw 'Expected separate connector and consumer authoring solutions.'
}
$centralMember = Invoke-Dataverse $session "solutioncomponents?`$filter=_solutionid_value eq $($central.value[0].solutionid) and componenttype eq 372 and objectid eq $($connector.connectorid)"
if ($centralMember.value.Count -ne 1) { throw 'Connector must be owned by the central solution before removing duplicate membership.' }
$duplicate = Invoke-Dataverse $session "solutioncomponents?`$filter=_solutionid_value eq $($consumer.value[0].solutionid) and componenttype eq 372 and objectid eq $($connector.connectorid)"
if ($duplicate.value.Count) {
    # PAC can include the custom connector despite AddRequiredComponents=false.
    Invoke-Dataverse $session 'RemoveSolutionComponent' POST @{
        SolutionComponent = @{ solutioncomponentid = $connector.connectorid }
        ComponentType = 372; SolutionUniqueName = 'ContosoPoCConsumer'
    } | Out-Null
}
@{
    workflowId = $flowRecord.workflowid; connectionReferenceId = $record.connectionreferenceid
    connectionReferenceLogicalName = 'contoso_ContosoProofConnection'; apiName = $ApiName
} | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot '..\out\consumer.local.json') -Encoding utf8
Write-Output 'Consumer flow and Connection Reference created in separate solution; bind a target Connection before activation.'
