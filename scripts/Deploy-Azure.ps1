[CmdletBinding()]
param(
    [Parameter(Mandatory)][Guid]$SubscriptionId,
    [Parameter(Mandatory)][Guid]$TenantId,
    [Parameter(Mandatory)][string]$Location,
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$PublisherName,
    [Parameter(Mandatory)][string]$PublisherEmail,
    [string]$Prefix = 'czconnector'
)
. "$PSScriptRoot\Common.ps1"
Assert-Tenant -TenantId $TenantId -SubscriptionId $SubscriptionId
$root = Split-Path $PSScriptRoot
$out = Join-Path $root 'out'
New-Item -ItemType Directory -Path $out -Force | Out-Null
& "$PSScriptRoot\Initialize-Entra.ps1" -TenantId $TenantId -SubscriptionId $SubscriptionId
$identity = Get-Content (Join-Path $out 'identity.local.json') -Raw | ConvertFrom-Json

$exists = Invoke-Az @('group', 'exists', '--subscription', "$SubscriptionId", '--name', $ResourceGroup)
if (($exists -join '').Trim() -eq 'true') {
    $group = Invoke-AzJson @('group', 'show', '--subscription', "$SubscriptionId", '--name', $ResourceGroup, '-o', 'json')
    if ($group.tags.purpose -ne 'cz-connector-poc') { throw 'Existing resource group is not demo-owned.' }
}
$deployment = Invoke-AzJson @('deployment', 'sub', 'create', '--subscription', "$SubscriptionId",
    '--location', $Location, '--name', 'cz-connector-poc',
    '--template-file', (Join-Path $root 'infra\deployment.bicep'), '--parameters',
    "resourceGroupName=$ResourceGroup",
    "location=$Location", "publisherName=$PublisherName", "publisherEmail=$PublisherEmail",
    "prefix=$Prefix", "tenantId=$TenantId", "backendClientId=$($identity.backendClientId)", '-o', 'json')
$values = $deployment.properties.outputs
$apimPrincipalId = $values.apimPrincipalId.value
$apimSp = Invoke-Graph -Path "servicePrincipals/$apimPrincipalId"
$assignments = Invoke-Graph -Path "servicePrincipals/$apimPrincipalId/appRoleAssignments"
if (-not ($assignments.value | Where-Object {
    $_.resourceId -eq $identity.backendPrincipalId -and $_.appRoleId -eq $identity.backendRoleId
})) {
    Invoke-Graph -Path "servicePrincipals/$apimPrincipalId/appRoleAssignments" -Method POST -Body @{
        principalId = $apimPrincipalId; resourceId = $identity.backendPrincipalId
        appRoleId = $identity.backendRoleId
    } | Out-Null
}
Invoke-Az @('webapp', 'config', 'appsettings', 'set', '--subscription', "$SubscriptionId",
    '--resource-group', $ResourceGroup, '--name', $values.backendName.value, '--settings',
    "Identity__ApimClientId=$($apimSp.appId)", '-o', 'none') | Out-Null

$publish = Join-Path $out 'backend'
& dotnet publish (Join-Path $root 'src\Backend\Backend.csproj') -c Release -o $publish --verbosity quiet
if ($LASTEXITCODE -ne 0) { throw 'Backend publish failed.' }
$zip = Join-Path $out 'backend.zip'
Compress-Archive -Path "$publish\*" -DestinationPath $zip -Force
Invoke-Az @('webapp', 'deploy', '--subscription', "$SubscriptionId", '--resource-group', $ResourceGroup,
    '--name', $values.backendName.value, '--src-path', $zip, '--type', 'zip', '-o', 'none') | Out-Null
Invoke-Az @('deployment', 'group', 'create', '--subscription', "$SubscriptionId", '--resource-group',
    $ResourceGroup, '--name', 'cz-api', '--template-file', (Join-Path $root 'infra\api.bicep'),
    '--parameters', "apimName=$($values.apimName.value)", "backendUrl=$($values.backendUrl.value)",
    "tenantId=$TenantId", "frontendClientId=$($identity.frontendClientId)",
    "connectorClientId=$($identity.connectorClientId)", "backendClientId=$($identity.backendClientId)",
    '-o', 'none') | Out-Null
$state = [ordered]@{
    resourceGroup = $ResourceGroup; location = $Location
    apimName = $values.apimName.value; apimPrincipalId = $apimPrincipalId; apimClientId = $apimSp.appId
    gatewayUrl = $values.gatewayUrl.value; backendName = $values.backendName.value
    backendUrl = $values.backendUrl.value
}
$state | ConvertTo-Json | Set-Content (Join-Path $out 'azure.local.json') -Encoding utf8
Write-Output 'Azure deployment complete. Identifiers saved under out; subscription keys were not exported.'
