$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\ConnectorSecurity.ps1"
$overlay = Get-Content (Join-Path $PSScriptRoot '..\connector\auth-overlay.json') -Raw | ConvertFrom-Json
$before = @{
    connectionparameters = $overlay.properties.connectionParameters | ConvertTo-Json -Depth 30 -Compress
    connectionparametersets = ''
    policytemplateinstances = ConvertTo-Json -InputObject @($overlay.properties.policyTemplateInstances) -Depth 30 -Compress
}
$after = $before.Clone()
Assert-ConnectorSecurityUnchanged -Before $before -After $after
$after.policytemplateinstances = '[]'
$rejected = $false
try { Assert-ConnectorSecurityUnchanged -Before $before -After $after }
catch {
    if ($_.Exception.Message -ne 'Connector security metadata changed unexpectedly: policytemplateinstances.') { throw }
    $rejected = $true
}
if (-not $rejected) { throw 'Regression: omitted-properties policy loss escaped the promotion guard.' }
Write-Output 'PASS: unchanged properties accepted; omitted-properties policy loss rejected before promotion.'
