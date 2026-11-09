[CmdletBinding()]
param(
    [Parameter(Mandatory)][Uri]$SourceEnvironmentUrl,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\out\solutions')
)
. "$PSScriptRoot\Common.ps1"
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
Invoke-Pac @('solution', 'publish', '--environment', $SourceEnvironmentUrl.AbsoluteUri)
foreach ($name in @('ContosoPoCConnector', 'ContosoPoCConsumer')) {
    Invoke-Pac @('solution', 'export', '--environment', $SourceEnvironmentUrl.AbsoluteUri,
        '--name', $name, '--path', (Join-Path $OutputDirectory "${name}_managed.zip"),
        '--managed', '--overwrite')
}
& "$PSScriptRoot\Test-ManagedPackages.ps1" -SolutionDirectory $OutputDirectory
Write-Output 'Managed solution packages exported. Import the connector before the consumer; configure target federation and delegated Connection before binding.'
