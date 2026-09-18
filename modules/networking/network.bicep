@description('Azure Region housing the resources')
param location string = resourceGroup().location

@description('Address space for the virtual network')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Address prefix for the subnet')
param subnetAddressPrefix string = '10.0.1.0/24'

resource vnet 'Microsoft.Network/virtualNetworks@2025-09-01' = {
  name: 'vnet-web-app'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'subnet-web-app'
        properties: {
          addressPrefix: subnetAddressPrefix
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output subnetId string = vnet.properties.subnets[0].id

