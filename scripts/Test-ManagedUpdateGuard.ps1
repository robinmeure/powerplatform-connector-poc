$ErrorActionPreference = 'Stop'
$directory = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $directory | Out-Null
$beforePath = Join-Path $directory 'before.json'
$afterPath = Join-Path $directory 'after.json'
try {
    $before = @{
        environmentId = 'target'; connectorId = 'connector'; connectorApiName = 'api'
        connectionReferenceId = 'reference'; connectionReferenceLogicalName = 'logical'
        connectionId = 'original'; referenceConnectorId = 'api'; workflowId = 'flow'
        connectionParametersSha256 = 'oauth-key'; connectionParameterSetsSha256 = 'sets'
        policyTemplateInstancesSha256 = 'original-policy'; definitionSha256 = 'old'
        connectorSolutionVersion = '1.0.0.1'; flowState = 1
    }
    $after = $before.Clone()
    $after.definitionSha256 = 'new'
    $after.connectorSolutionVersion = '1.0.1.0'
    $after.policyTemplateInstancesSha256 = 'different-wrapper-casing'
    $after.policyTemplateInstancesNormalizedSha256 = 'original-policy'
    $before | ConvertTo-Json | Set-Content $beforePath
    $after | ConvertTo-Json | Set-Content $afterPath
    & "$PSScriptRoot\Test-ManagedUpdate.ps1" -BeforePath $beforePath -AfterPath $afterPath
    foreach ($mutation in @(
        @{ field = 'definitionSha256'; value = 'old'; error = '*effective connector definition did not*' },
        @{ field = 'connectionParametersSha256'; value = 'source-oauth'; error = '*did not preserve connectionParametersSha256*' },
        @{ field = 'connectionId'; value = 'replacement'; error = '*did not preserve connectionId*' },
        @{ field = 'policyTemplateInstancesNormalizedSha256'; value = 'lost-policy'; error = '*did not preserve the header policy*' }
    )) {
        $changed = $after.Clone()
        $changed[$mutation.field] = $mutation.value
        $changed | ConvertTo-Json | Set-Content $afterPath
        $rejected = $false
        try { & "$PSScriptRoot\Test-ManagedUpdate.ps1" -BeforePath $beforePath -AfterPath $afterPath }
        catch {
            if ($_.Exception.Message -notlike $mutation.error) { throw }
            $rejected = $true
        }
        if (-not $rejected) { throw "Regression: $($mutation.field) mutation escaped the guard." }
    }
    Write-Output 'PASS: version-only update, wrong OAuth identity, replaced Connection and lost header policy are rejected.'
}
finally {
    foreach ($path in @($beforePath, $afterPath)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
    Remove-Item -LiteralPath $directory
}
