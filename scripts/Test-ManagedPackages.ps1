[CmdletBinding()]
param([string]$SolutionDirectory = (Join-Path $PSScriptRoot '..\out\solutions'))
$ErrorActionPreference = 'Stop'
foreach ($name in @('ContosoPoCConnector', 'ContosoPoCConsumer')) {
    $zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $SolutionDirectory "${name}_managed.zip"))
    try {
        $connectorFiles = @($zip.Entries | Where-Object { $_.FullName.StartsWith('Connector/') })
        if ($name -eq 'ContosoPoCConsumer' -and $connectorFiles.Count) {
            throw 'Consumer package contains the centrally owned connector; separate solution ownership before promotion.'
        }
        if ($name -eq 'ContosoPoCConnector' -and -not $connectorFiles.Count) {
            throw 'Connector package has no connector artifacts.'
        }
    }
    finally { $zip.Dispose() }
}
Write-Output 'Managed packages have separate connector and consumer ownership.'
