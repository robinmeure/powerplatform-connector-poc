. "$PSScriptRoot\Common.ps1"

function New-DemoDataverseSession {
    param(
        [Parameter(Mandatory)][Guid]$TenantId,
        [Parameter(Mandatory)][Guid]$SubscriptionId,
        [Parameter(Mandatory)][Guid]$EnvironmentId,
        [Parameter(Mandatory)][Uri]$EnvironmentUrl,
        [Parameter(Mandatory)][ValidateSet('Contoso Connector PoC Build', 'Contoso Connector PoC')][string]$ExpectedName,
        [ValidateSet('europe', 'switzerland')][string]$ExpectedLocation = 'europe'
    )
    Assert-Tenant -TenantId $TenantId -SubscriptionId $SubscriptionId
    if ($EnvironmentUrl.Scheme -ne 'https' -or -not $EnvironmentUrl.Host.EndsWith('.dynamics.com') -or $EnvironmentUrl.UserInfo) {
        throw 'Expected an HTTPS Dataverse organization URL.'
    }
    $powerPlatformToken = Invoke-AzJson @('account', 'get-access-token', '--subscription', "$SubscriptionId",
        '--resource', 'https://service.powerapps.com/', '-o', 'json')
    $environment = Invoke-RestMethod `
        -Uri "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/environments/$($EnvironmentId)?api-version=2020-10-01" `
        -Headers @{ Authorization = "Bearer $($powerPlatformToken.accessToken)" }
    if ($environment.location -ne $ExpectedLocation -or $environment.properties.displayName -ne $ExpectedName -or
        $environment.properties.tenantId -ne "$TenantId" -or $environment.properties.environmentSku -ne 'Developer') {
        throw 'Environment does not match the explicitly approved demo name, tenant, location and Developer type.'
    }
    if ($environment.properties.provisioningState -ne 'Succeeded' -or
        $environment.properties.linkedEnvironmentMetadata.instanceState -ne 'Ready') {
        throw 'The demo environment and Dataverse instance must both be ready.'
    }
    $actualUrl = $environment.properties.linkedEnvironmentMetadata.instanceUrl
    if ([string]::IsNullOrEmpty($actualUrl) -or ([Uri]$actualUrl).Host -ne $EnvironmentUrl.Host) {
        throw 'Organization URL does not match the approved environment.'
    }
    $access = Invoke-AzJson @('account', 'get-access-token', '--subscription', "$SubscriptionId",
        '--resource', $EnvironmentUrl.AbsoluteUri, '-o', 'json')
    return @{
        baseUrl = "$($EnvironmentUrl.AbsoluteUri.TrimEnd('/'))/api/data/v9.2"
        headers = @{
            Authorization = "Bearer $($access.accessToken)"
            Accept = 'application/json'; 'OData-Version' = '4.0'; 'OData-MaxVersion' = '4.0'
            Prefer = 'return=representation'
        }
    }
}

function Invoke-Dataverse {
    param([hashtable]$Session, [string]$Path, [string]$Method = 'GET', [object]$Body)
    $parameters = @{
        Uri = "$($Session.baseUrl)/$Path"; Method = $Method; Headers = $Session.headers
        ContentType = 'application/json'
    }
    if ($null -ne $Body) { $parameters.Body = $Body | ConvertTo-Json -Depth 100 }
    Invoke-RestMethod @parameters
}
