targetScope = 'subscription'

param location string
param resourceGroupName string
param publisherName string
param publisherEmail string
param prefix string = 'czconnector'
param tenantId string
param backendClientId string

resource group 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: { purpose: 'cz-connector-poc' }
}
module resources './main.bicep' = {
  name: 'cz-infrastructure'
  scope: group
  params: {
    location: location
    publisherName: publisherName
    publisherEmail: publisherEmail
    prefix: prefix
    tenantId: tenantId
    backendClientId: backendClientId
  }
}
output apimName string = resources.outputs.apimName
output apimPrincipalId string = resources.outputs.apimPrincipalId
output gatewayUrl string = resources.outputs.gatewayUrl
output backendName string = resources.outputs.backendName
output backendUrl string = resources.outputs.backendUrl
