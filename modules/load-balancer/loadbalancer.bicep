@description('Azure Region housing the resources')
param location string = resourceGroup().location

resource publicIp 'Microsoft.Network/publicIPAddresses@2025-09-01' = {
  name: 'pip-webapp-lb'
  location: location
  properties: {
    publicIPAllocationMethod: 'Static'
  }
  sku: {
    name: 'Standard'
  }
}

resource loadBalancer 'Microsoft.Network/loadBalancers@2025-09-01' = {
  name: 'lb-webapp'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'lb-frontend'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'lb-backend-pool'
      }
    ]
    probes: [
      {
        name: 'lb-health-probe'
        properties: {
          protocol: 'Http'
          port: 80
          requestPath: '/'
          intervalInSeconds: 15
          numberOfProbes: 2
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'lb-rule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'lb-webapp', 'lb-frontend')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'lb-webapp', 'lb-backend-pool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', 'lb-webapp', 'lb-health-probe')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
        }
      }
    ]
  }
}

output loadBalancerId string = loadBalancer.id
output publicIpId string = publicIp.id
output backendPoolId string = loadBalancer.properties.backendAddressPools[0].id
output frontendIpId string = loadBalancer.properties.frontendIPConfigurations[0].id
output healthProbeId string = loadBalancer.properties.probes[0].id
output publicIpAddress string = publicIp.properties.ipAddress
