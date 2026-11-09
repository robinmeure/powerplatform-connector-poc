[CmdletBinding()]
param(
    [Parameter(Mandatory)][Guid]$TenantId,
    [Parameter(Mandatory)][Guid]$SubscriptionId,
    [Parameter(Mandatory)][ValidateSet('Contoso Connector PoC Build', 'Contoso Connector PoC')][string]$DisplayName,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$DomainName,
    [string]$ModulePath = 'Microsoft.PowerApps.Administration.PowerShell'
)
. "$PSScriptRoot\Common.ps1"
Assert-Tenant -TenantId $TenantId -SubscriptionId $SubscriptionId

# Macro-region selection can place an environment outside the Europe geography.
Import-Module $ModulePath -DisableNameChecking -ErrorAction Stop
Add-PowerAppsAccount -Endpoint prod -TenantID "$TenantId" -UseSystemBrowser $true -ErrorAction Stop
if ($global:currentSession.tenantId -ne "$TenantId") { throw 'Power Platform login belongs to a different tenant.' }
$existing = @(Get-AdminPowerAppEnvironment | Where-Object { $_.DisplayName -eq $DisplayName })
if ($existing.Count) { throw 'An environment with this display name already exists. Inspect it before creating another.' }
$response = New-AdminPowerAppEnvironment -DisplayName $DisplayName -LocationName europe `
    -EnvironmentSku Developer -ProvisionDatabase -CurrencyName EUR -LanguageName 1033 `
    -DomainName $DomainName -WaitUntilFinished $true -TimeoutInMinutes 30 -ErrorAction Stop
if (-not $response.PSObject.Properties['EnvironmentName']) {
    $detail = $response | Select-Object Code,Description,Error,Errors | ConvertTo-Json -Depth 10 -Compress
    throw "Environment creation did not return a completed environment: $detail"
}
if ($response.Location -ne 'europe') { throw "Environment was created outside Europe: $($response.Location). Do not deploy components." }
$state = [ordered]@{
    displayName = $DisplayName
    requestedLocation = 'europe'
    environmentId = $response.EnvironmentName
    verifiedLocation = $response.Location
    environmentType = $response.EnvironmentType
}
$path = Join-Path $PSScriptRoot "..\out\environment-$DomainName.local.json"
$state | ConvertTo-Json -Depth 30 | Set-Content -Path $path -Encoding utf8
Write-Output "Creation request recorded at $path. Verify completed environment location before deployment."
