@description('Azure Region housing the resources')
param location string = resourceGroup().location

@description('Resource ID of the subnet housing the web apps')
param subnetId string 

@description('Resource ID of the load balancer backend pool')
param backendPoolId string

@description('Resource ID of the load balancer health probe')
param healthProbeId string

@description('Admin Username for the web app VM')
param adminUsername string

@description('Admin Password for the web app VM')
@secure()
param adminPassword string

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2026-04-01' = {
  name: 'vmss-webapp'
  location: location
  sku: {
    name: 'Standard_B1s'
    tier: 'Standard'
    capacity: 3
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Rolling'
      rollingUpgradePolicy: {
        maxBatchInstancePercent: 34
        maxUnhealthyInstancePercent: 34
        maxUnhealthyUpgradedInstancePercent: 34
        pauseTimeBetweenBatches: 'PT0S'
      }
    }
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: 'webvm'
        adminUsername: adminUsername
        adminPassword: adminPassword
        linuxConfiguration: {
          disablePasswordAuthentication: false
        }
        customData: base64('''#cloud-config
package_update: true
packages:
  - nginx
runcmd:
  - systemctl enable nginx
  - systemctl start nginx
''')
      }
      storageProfile: {
        imageReference: {
          publisher: 'Canonical'
          offer: 'ubuntu-24_04-lts'
          sku: 'server'
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'Standard_LRS'
          }
        }
      }
      networkProfile: {
        healthProbe: {
          id: healthProbeId
        } 
        networkInterfaceConfigurations: [
          {
            name: 'nic-webapp'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig-webapp'
                  properties: {
                    subnet: {
                      id: subnetId
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: backendPoolId
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
    }
  }
}
