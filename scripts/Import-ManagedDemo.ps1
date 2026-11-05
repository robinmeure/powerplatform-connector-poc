[CmdletBinding()]
param(
    [Parameter(Mandatory)][Guid]$TenantId,
    [Parameter(Mandatory)][Guid]$SubscriptionId,
    [Parameter(Mandatory)][Guid]$EnvironmentId,
    [Parameter(Mandatory)][Uri]$EnvironmentUrl,
    [ValidateSet('europe', 'switzerland')][string]$ExpectedLocation = 'europe',
    [Parameter(Mandatory)][ValidateSet('Connector', 'Consumer')][string]$Stage,
    [switch]$StageAndUpgrade,
    [string]$ConnectionId,
    [string]$SolutionDirectory = (Join-Path $PSScriptRoot '..\out\solutions')
)
. "$PSScriptRoot\Dataverse.ps1"
& "$PSScriptRoot\Test-ManagedPackages.ps1" -SolutionDirectory $SolutionDirectory
$session = New-DemoDataverseSession -TenantId $TenantId -SubscriptionId $SubscriptionId `
    -EnvironmentId $EnvironmentId -EnvironmentUrl $EnvironmentUrl -ExpectedName 'CZ Connector PoC' `
    -ExpectedLocation $ExpectedLocation
$name = "CZPoC$Stage"
$path = Join-Path $SolutionDirectory "${name}_managed.zip"
$zip = [IO.Compression.ZipFile]::OpenRead($path)
try {
    $entry = $zip.GetEntry('solution.xml')
    if (-not $entry) { throw 'Package has no solution.xml.' }
    $reader = [IO.StreamReader]::new($entry.Open())
    try { $manifest = [xml]$reader.ReadToEnd() } finally { $reader.Dispose() }
    $solution = $manifest.ImportExportXml.SolutionManifest
    if ($solution.UniqueName -ne $name -or [string]$solution.Managed -ne '1') {
        throw 'Expected the named managed demo solution package.'
    }
}
finally { $zip.Dispose() }
$arguments = @('solution', 'import', '--environment', $EnvironmentUrl.AbsoluteUri, '--path', $path)
if ($StageAndUpgrade) { $arguments += '--stage-and-upgrade' }
if ($Stage -eq 'Consumer') {
    if ([string]::IsNullOrWhiteSpace($ConnectionId)) { throw 'Consumer import requires an existing target delegated Connection ID.' }
    $connectors = Invoke-Dataverse $session "connectors?`$filter=displayname eq 'CZ Connector Proof'"
    if ($connectors.value.Count -ne 1) { throw 'Import and configure the target connector first.' }
    $settings = @{
        EnvironmentVariables = @()
        ConnectionReferences = @(@{
            LogicalName = 'cz_CZProofConnection'; ConnectionId = $ConnectionId
            ConnectorId = "/providers/Microsoft.PowerApps/apis/$($connectors.value[0].connectorinternalid)"
        })
    }
    $settingsPath = Join-Path $PSScriptRoot '..\out\deploymentSettings.consumer.local.json'
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding utf8
    $arguments += @('--settings-file', $settingsPath)
}
Invoke-Pac -Arguments $arguments
Write-Output "Managed $Stage solution imported. Verify federation/Connection and execute the real consumer flow before claiming proof."
