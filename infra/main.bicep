targetScope = 'resourceGroup'

param location string
param publisherName string
param publisherEmail string
@minLength(3)
@maxLength(20)
param prefix string = 'contosoconnector'
param tenantId string
param backendClientId string

var suffix = uniqueString(resourceGroup().id)
var tags = { purpose: 'contoso-connector-poc' }

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: '${prefix}-apim-${suffix}'
  location: location
  tags: tags
  sku: { name: 'Developer', capacity: 1 }
  identity: { type: 'SystemAssigned' }
  properties: {
    publisherName: publisherName
    publisherEmail: publisherEmail
  }
}

resource plan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: '${prefix}-plan-${suffix}'
  location: location
  tags: tags
  kind: 'linux'
  sku: { name: 'B1', tier: 'Basic', capacity: 1 }
  properties: { reserved: true }
}

resource backend 'Microsoft.Web/sites@2024-11-01' = {
  name: '${prefix}-api-${suffix}'
  location: location
  tags: tags
  kind: 'app,linux'
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|10.0'
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      appSettings: [
        { name: 'Identity__TenantId', value: tenantId }
        { name: 'Identity__Audience', value: backendClientId }
        { name: 'Identity__ApimPrincipalId', value: apim.identity.principalId }
        // Resolved from the APIM service principal before application deployment.
        { name: 'Identity__ApimClientId', value: '00000000-0000-0000-0000-000000000000' }
        { name: 'Demo__Version', value: '1.0.0' }
      ]
    }
  }
}

output apimName string = apim.name
output apimPrincipalId string = apim.identity.principalId
output gatewayUrl string = apim.properties.gatewayUrl
output backendName string = backend.name
output backendUrl string = 'https://${backend.properties.defaultHostName}'
