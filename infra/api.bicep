targetScope = 'resourceGroup'

param apimName string
param backendUrl string
param tenantId string
param frontendClientId string
param connectorClientId string
param backendClientId string

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = { name: apimName }
resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'cz-proof'
  properties: {
    displayName: 'CZ Connector Proof'
    path: 'cz'
    protocols: [ 'https' ]
    subscriptionRequired: true
    serviceUrl: backendUrl
    format: 'swagger-json'
    value: loadTextContent('../connector/apiDefinition.json')
  }
}

var policy = replace(replace(replace(replace(loadTextContent('./policies/api.xml'),
  '__TENANT_ID__', tenantId), '__FRONTEND_ID__', frontendClientId),
  '__CONNECTOR_ID__', connectorClientId), '__BACKEND_RESOURCE__', 'api://${backendClientId}')

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: api
  name: 'policy'
  properties: { format: 'rawxml', value: policy }
}

resource product 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  parent: apim
  name: 'cz-developers'
  properties: {
    displayName: 'CZ Developers'
    description: 'Subscription key and delegated Entra authorization are both required.'
    subscriptionRequired: true
    approvalRequired: true
    subscriptionsLimit: 1
    state: 'published'
  }
}

resource productApi 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = {
  parent: product
  name: api.name
}

resource developerGroup 'Microsoft.ApiManagement/service/products/groups@2024-05-01' = {
  parent: product
  name: 'developers'
}

resource subscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apim
  name: 'cz-demo-connection'
  properties: {
    displayName: 'CZ demo connection'
    scope: product.id
    state: 'active'
    allowTracing: false
  }
}

output apiId string = api.id
output subscriptionId string = subscription.id
