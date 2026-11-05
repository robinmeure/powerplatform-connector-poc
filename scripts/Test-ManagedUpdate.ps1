[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BeforePath,
    [Parameter(Mandatory)][string]$AfterPath
)
$ErrorActionPreference = 'Stop'
$before = Get-Content -LiteralPath $BeforePath -Raw | ConvertFrom-Json
$after = Get-Content -LiteralPath $AfterPath -Raw | ConvertFrom-Json
foreach ($field in @('environmentId', 'connectorId', 'connectorApiName', 'connectionReferenceId',
    'connectionReferenceLogicalName', 'connectionId', 'referenceConnectorId', 'workflowId',
    'connectionParametersSha256', 'connectionParameterSetsSha256')) {
    if ($before.$field -ne $after.$field) { throw "Managed update did not preserve $field." }
}
if ($before.policyTemplateInstancesSha256 -ne $after.policyTemplateInstancesSha256 -and
    $before.policyTemplateInstancesSha256 -ne $after.policyTemplateInstancesNormalizedSha256) {
    throw 'Managed update did not preserve the header policy, including all parameter values.'
}
if ([version]$after.connectorSolutionVersion -le [version]$before.connectorSolutionVersion) {
    throw 'Managed connector solution version did not increase.'
}
if ($before.definitionSha256 -eq $after.definitionSha256) {
    throw 'Managed version changed but effective connector definition did not; inspect solution layers.'
}
if ($after.flowState -ne 1) { throw 'Original managed flow is not active.' }
Write-Output 'PASS: effective definition changed; original components, binding and security fingerprints preserved. A real flow rerun and federation verification are still required.'
