#requires -Version 7.1

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$Version = '1.0.1'
)
$ErrorActionPreference = 'Stop'
$definition = Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json -Depth 100 -AsHashtable
$definition.info.version = $Version
$definition.paths.'/proof'.get.summary = 'Get identity-boundary proof (compatible update)'
$definition.paths.'/proof'.get.description = 'Compatible managed update: verifies the APIM application identity while preserving the original Connection.'
New-Item -ItemType Directory -Path (Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))) -Force | Out-Null
$definition | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding utf8
