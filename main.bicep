@description('Azure region housing the resources')
param location string = resourceGroup().location

@description('Admin username for the VM')
param adminUsername string

@description('Admin password for the VM')
@secure()
param adminPassword string

module networking 'modules/networking/network.bicep' = {
  name: 'networkingDeployment'
  params: {
    location: location
  }
}

module loadBalancer 'modules/load-balancer/loadbalancer.bicep' = {
  name: 'loadBalancerDeployment'
  params: {
    location: location
  }
}

module compute 'modules/compute/compute.bicep' = {
  name: 'computeDeployment'
  params: {
    location: location
    subnetId: networking.outputs.subnetId
    backendPoolId: loadBalancer.outputs.backendPoolId
    healthProbeId: loadBalancer.outputs.healthProbeId
    adminUsername: adminUsername
    adminPassword: adminPassword
  }
}

output loadBalancerPublicIp string = loadBalancer.outputs.publicIpAddress
