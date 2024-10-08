﻿// --------------------------------------------------------------------------------
// Main Bicep file that deploys the Azure Resources for a Function App
// Note: Bicep modules are used from the repository defined in bicepconfig.json
// --------------------------------------------------------------------------------
// NOTE: To make this pipeline work, your service principal may need to be in the
//   "acr pull" role for the container registry.
// --------------------------------------------------------------------------------
@allowed(['dev','demo','qa','stg','prod'])
param environmentCode string = 'dev'
param location string = resourceGroup().location
param orgPrefix string = 'org'
param appPrefix string = 'app'
param appSuffix string = '' // '-1' 
@allowed(['Standard_LRS','Standard_GRS','Standard_RAGRS'])
param storageSku string = 'Standard_LRS'
param functionAppSku string = 'Y1'
param functionAppSkuFamily string = 'Y'
param functionAppSkuTier string = 'Dynamic'
param keyVaultOwnerUserId1 string = ''
param keyVaultOwnerUserId2 string = ''
param runDateTime string = utcNow()

// --------------------------------------------------------------------------------
var deploymentSuffix = '-${runDateTime}'
var commonTags = {         
  LastDeployed: runDateTime
  Application: appPrefix
  Organization: orgPrefix
  Environment: environmentCode
}
var cosmosDatabaseName = 'FuncDemoDatabase'
var cosmosOrdersContainerDbName = 'orders'
var cosmosOrdersContainerDbKey = '/customerNumber'
var cosmosProductsContainerDbName = 'products'
var cosmosProductsContainerDbKey = '/category'

var svcBusQueueOrders = 'orders-received'
var svcBusQueueERP =  'orders-to-erp' 

// --------------------------------------------------------------------------------
module resourceNames 'resourcenames.bicep' = {
  name: 'resourcenames${deploymentSuffix}'
  params: {
    orgPrefix: orgPrefix
    appPrefix: appPrefix
    environment: environmentCode
    appSuffix: appSuffix
    functionName: 'process'
    functionStorageNameSuffix: 'store'
    dataStorageNameSuffix: 'data'
  }
}

// --------------------------------------------------------------------------------
module functionStorageModule 'br/mybicepregistry:storageaccount:LATEST' = {
  name: 'functionstorage${deploymentSuffix}'
  params: {
    storageSku: storageSku
    storageAccountName: resourceNames.outputs.functionStorageName
    location: location
    commonTags: commonTags
  }
}
module servicebusModule 'br/mybicepregistry:servicebus:LATEST' = {
  name: 'servicebus${deploymentSuffix}'
  params: {
    serviceBusName: resourceNames.outputs.serviceBusName
    queueNames: [ svcBusQueueOrders, svcBusQueueERP ]
    location: location
    commonTags: commonTags
  }
}
var cosmosContainerArray = [
  { name: cosmosProductsContainerDbName, partitionKey: cosmosProductsContainerDbKey }
  { name: cosmosOrdersContainerDbName, partitionKey: cosmosOrdersContainerDbKey }
]
module cosmosModule 'br/mybicepregistry:cosmosdatabase:LATEST' = {
  name: 'cosmos${deploymentSuffix}'
  params: {
    cosmosAccountName: resourceNames.outputs.cosmosAccountName
    containerArray: cosmosContainerArray
    cosmosDatabaseName: cosmosDatabaseName

    location: location
    commonTags: commonTags
  }
}
module functionModule 'br/mybicepregistry:functionapp:LATEST' = {
  name: 'function${deploymentSuffix}'
  dependsOn: [ functionStorageModule ]
  params: {
    functionAppName: resourceNames.outputs.functionAppName
    functionAppServicePlanName: resourceNames.outputs.functionAppServicePlanName
    functionInsightsName: resourceNames.outputs.functionInsightsName

    appInsightsLocation: location
    location: location
    commonTags: commonTags

    functionKind: 'functionapp,linux'
    functionAppSku: functionAppSku
    functionAppSkuFamily: functionAppSkuFamily
    functionAppSkuTier: functionAppSkuTier
    functionStorageAccountName: functionStorageModule.outputs.name
  }
}
module keyVaultModule 'br/mybicepregistry:keyvault:LATEST' = {
  name: 'keyvault${deploymentSuffix}'
  dependsOn: [ functionModule ]
  params: {
    keyVaultName: resourceNames.outputs.keyVaultName
    location: location
    commonTags: commonTags
    adminUserObjectIds: [ keyVaultOwnerUserId1, keyVaultOwnerUserId2 ]
    applicationUserObjectIds: [ functionModule.outputs.principalId ]
  }
}
module keyVaultSecret1 'br/mybicepregistry:keyvaultsecret:LATEST' = {
  name: 'keyVaultSecret1${deploymentSuffix}'
  dependsOn: [ keyVaultModule, functionModule ]
  params: {
    keyVaultName: keyVaultModule.outputs.name
    secretName: 'functionAppInsightsKey'
    secretValue: functionModule.outputs.insightsKey
  }
}
module keyVaultSecret2 'br/mybicepregistry:keyvaultsecretcosmosconnection:LATEST' = {
  name: 'keyVaultSecret2${deploymentSuffix}'
  dependsOn: [ keyVaultModule, cosmosModule ]
  params: {
    keyVaultName: keyVaultModule.outputs.name
    keyName: 'cosmosConnectionString'
    cosmosAccountName: cosmosModule.outputs.name
  }
}
module keyVaultSecret3 'br/mybicepregistry:keyvaultsecretservicebusconnection:LATEST' = {
  name: 'keyVaultSecret3${deploymentSuffix}'
  dependsOn: [ keyVaultModule, servicebusModule ]
  params: {
    keyVaultName: keyVaultModule.outputs.name
    keyName: 'serviceBusSendConnectionString'
    serviceBusName: servicebusModule.outputs.name
    accessKeyName: 'send'
  }
}
module keyVaultSecret4 'br/mybicepregistry:keyvaultsecretservicebusconnection:LATEST' = {
  name: 'keyVaultSecret4${deploymentSuffix}'
  dependsOn: [ keyVaultModule, servicebusModule ]
  params: {
    keyVaultName: keyVaultModule.outputs.name
    keyName: 'serviceBusReceiveConnectionString'
    serviceBusName: servicebusModule.outputs.name
    accessKeyName: 'listen'
  }
}
module keyVaultSecret5 'br/mybicepregistry:keyvaultsecretstorageconnection:LATEST' = {
  name: 'keyVaultSecret5${deploymentSuffix}'
  dependsOn: [ keyVaultModule, functionStorageModule ]
  params: {
    keyVaultName: keyVaultModule.outputs.name
    keyName: 'functionStorageAccountConnectionString'
    storageAccountName: functionStorageModule.outputs.name
  }
}
module functionAppSettingsModule 'br/mybicepregistry:functionappsettings:LATEST' = {
  name: 'functionAppSettings${deploymentSuffix}'
  dependsOn: [ keyVaultSecret1, keyVaultSecret2, keyVaultSecret3, keyVaultSecret4, keyVaultSecret5, functionModule ]
  params: {
    functionAppName: functionModule.outputs.name
    functionStorageAccountName: functionModule.outputs.storageAccountName
    functionInsightsKey: functionModule.outputs.insightsKey
    customAppSettings: {
      cosmosDatabaseName: cosmosDatabaseName
      cosmosContainerName: cosmosProductsContainerDbName
      ordersContainerName: cosmosOrdersContainerDbName
      orderReceivedQueue: svcBusQueueOrders
      cosmosConnectionStringReference: '@Microsoft.KeyVault(VaultName=${keyVaultModule.outputs.name};SecretName=cosmosConnectionString)'
      serviceBusReceiveConnectionStringReference: '@Microsoft.KeyVault(VaultName=${keyVaultModule.outputs.name};SecretName=serviceBusReceiveConnectionString)'
      serviceBusSendConnectionStringReference: '@Microsoft.KeyVault(VaultName=${keyVaultModule.outputs.name};SecretName=serviceBusSendConnectionString)'
    }
  }
}
