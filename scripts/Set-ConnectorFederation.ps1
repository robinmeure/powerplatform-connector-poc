[CmdletBinding()]
param(
    [Parameter(Mandatory)][Uri]$Issuer,
    [Parameter(Mandatory)][string]$Subject,
    [Parameter(Mandatory)][Uri]$RedirectUri,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9-]{3,80}$')][string]$CredentialName,
    [string]$IdentityPath = (Join-Path $PSScriptRoot '..\out\identity.local.json')
)
. "$PSScriptRoot\Common.ps1"
$identity = Get-Content -LiteralPath $IdentityPath -Raw | ConvertFrom-Json
Assert-Tenant -TenantId $identity.tenantId -SubscriptionId $identity.subscriptionId
if ($Issuer.Scheme -ne 'https' -or $Issuer.UserInfo -or
    $Issuer.Host -notin @('login.microsoftonline.com', 'sts.windows.net')) {
    throw 'Use the Entra issuer shown by the connector, not an arbitrary federation issuer.'
}
if ($RedirectUri.Scheme -ne 'https' -or $RedirectUri.UserInfo -or
    -not $RedirectUri.Host.EndsWith('.consent.azure-apim.net')) {
    throw 'Use the exact HTTPS consent.azure-apim.net redirect URI shown by the connector.'
}
$app = Invoke-Graph -Path "applications/$($identity.connectorObjectId)"
if ($app.tags -notcontains 'CZConnectorPoC' -or $app.appId -ne $identity.connectorClientId) {
    throw 'Connector client registration is not the demo-owned application.'
}
$credentials = Invoke-Graph -Path "applications/$($app.id)/federatedIdentityCredentials"
$existing = @($credentials.value | Where-Object { $_.name -eq $CredentialName })
if ($existing.Count) {
    if ($existing.Count -ne 1 -or $existing[0].issuer -ne $Issuer.AbsoluteUri -or
        $existing[0].subject -ne $Subject -or $existing[0].audiences -notcontains 'api://AzureADTokenExchange') {
        throw 'Existing named federation credential has different identity details.'
    }
}
else {
    Invoke-Graph -Path "applications/$($app.id)/federatedIdentityCredentials" -Method POST -Body @{
        name = $CredentialName; issuer = $Issuer.AbsoluteUri; subject = $Subject
        audiences = @('api://AzureADTokenExchange')
    } | Out-Null
}
$redirects = @($app.web.redirectUris)
if ($redirects -notcontains $RedirectUri.AbsoluteUri) {
    Invoke-Graph -Path "applications/$($app.id)" -Method PATCH -Body @{
        web = @{ redirectUris = @($redirects + $RedirectUri.AbsoluteUri) }
    } | Out-Null
}
Write-Output 'Connector federation and redirect registered. No client secret was created.'
