[CmdletBinding()]
param(
    [Parameter(Mandatory)][Guid]$TenantId,
    [Parameter(Mandatory)][Guid]$SubscriptionId,
    [ValidatePattern('^[a-zA-Z0-9-]{3,40}$')][string]$Prefix = 'cz-connector-poc',
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\out\identity.local.json')
)
. "$PSScriptRoot\Common.ps1"
Assert-Tenant -TenantId $TenantId -SubscriptionId $SubscriptionId

$scopeId = 'cd6d85de-f828-42f2-b5c4-987becd3c71d'
$roleId = 'eeb274c6-855c-46c7-920c-79c4fd21f507'

function Get-OrCreateApplication {
    param([string]$Name, [hashtable]$Properties)
    $found = Invoke-Graph -Path ("applications?`$filter=" + [Uri]::EscapeDataString("displayName eq '$Name'"))
    if ($found.value.Count -gt 1) { throw "Ambiguous application display name: $Name" }
    if ($found.value.Count -eq 1) {
        $app = $found.value[0]
        if ($app.tags -notcontains 'CZConnectorPoC') { throw "Application is not demo-owned: $Name" }
        Invoke-Graph -Path "applications/$($app.id)" -Method PATCH -Body $Properties | Out-Null
        return $app
    }
    return Invoke-Graph -Path 'applications' -Method POST -Body ($Properties + @{
        displayName = $Name; tags = @('CZConnectorPoC')
    })
}

function Get-OrCreateServicePrincipal {
    param([string]$ApplicationId)
    $found = Invoke-Graph -Path ("servicePrincipals?`$filter=" + [Uri]::EscapeDataString("appId eq '$ApplicationId'"))
    if ($found.value.Count -eq 1) { return $found.value[0] }
    return Invoke-Graph -Path 'servicePrincipals' -Method POST -Body @{ appId = $ApplicationId }
}

$frontend = Get-OrCreateApplication "$Prefix-frontend" @{
    signInAudience = 'AzureADMyOrg'
    api = @{
        requestedAccessTokenVersion = 2
        oauth2PermissionScopes = @(@{
            id = $scopeId; value = 'Demo.Read'; type = 'Admin'; isEnabled = $true
            adminConsentDisplayName = 'Invoke the CZ demo through APIM'
            adminConsentDescription = 'Allows delegated access to the CZ demonstration API.'
        })
    }
}
Invoke-Graph -Path "applications/$($frontend.id)" -Method PATCH -Body @{
    identifierUris = @("api://$($frontend.appId)")
} | Out-Null
$frontendSp = Get-OrCreateServicePrincipal $frontend.appId

$backend = Get-OrCreateApplication "$Prefix-backend" @{
    signInAudience = 'AzureADMyOrg'
    api = @{ requestedAccessTokenVersion = 2 }
    optionalClaims = @{ accessToken = @(@{ name = 'idtyp'; essential = $false; additionalProperties = @() }) }
    appRoles = @(@{
        id = $roleId; value = 'Demo.Invoke'; displayName = 'Invoke CZ backend'
        description = 'Allows the APIM application identity to invoke the backend.'
        allowedMemberTypes = @('Application'); isEnabled = $true
    })
}
Invoke-Graph -Path "applications/$($backend.id)" -Method PATCH -Body @{
    identifierUris = @("api://$($backend.appId)")
} | Out-Null
$backendSp = Get-OrCreateServicePrincipal $backend.appId

$connector = Get-OrCreateApplication "$Prefix-connector" @{
    signInAudience = 'AzureADMyOrg'
    requiredResourceAccess = @(@{
        resourceAppId = $frontend.appId
        resourceAccess = @(@{ id = $scopeId; type = 'Scope' })
    })
}
$connectorSp = Get-OrCreateServicePrincipal $connector.appId
$grants = Invoke-Graph -Path ("oauth2PermissionGrants?`$filter=" +
    [Uri]::EscapeDataString("clientId eq '$($connectorSp.id)' and resourceId eq '$($frontendSp.id)'"))
if ($grants.value.Count -eq 0) {
    Invoke-Graph -Path 'oauth2PermissionGrants' -Method POST -Body @{
        clientId = $connectorSp.id; resourceId = $frontendSp.id
        consentType = 'AllPrincipals'; scope = 'Demo.Read'
    } | Out-Null
}
elseif (-not ($grants.value | Where-Object { $_.consentType -eq 'AllPrincipals' -and $_.scope.Split(' ') -contains 'Demo.Read' })) {
    throw 'Existing consent does not include the required tenant-wide Demo.Read grant.'
}

$identity = [ordered]@{
    tenantId = "$TenantId"; subscriptionId = "$SubscriptionId"
    frontendClientId = $frontend.appId; frontendObjectId = $frontend.id
    backendClientId = $backend.appId; backendObjectId = $backend.id
    backendPrincipalId = $backendSp.id; backendRoleId = $roleId
    connectorClientId = $connector.appId; connectorObjectId = $connector.id
}
New-Item -ItemType Directory -Path (Split-Path $OutputPath) -Force | Out-Null
$identity | ConvertTo-Json | Set-Content -Path $OutputPath -Encoding utf8
Write-Output "Entra application identifiers saved to $OutputPath (no credentials generated)."
