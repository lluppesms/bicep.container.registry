// --------------------------------------------------------------------------------
// Main Bicep File to deploy all Azure Resources for App Insights
// --------------------------------------------------------------------------------
param environmentCode string = 'dev'
param location string = resourceGroup().location
param orgPrefix string = 'org'
param appPrefix string = 'app'
param appSuffix string = '' // '-1' 
param runDateTime string = utcNow()

// --------------------------------------------------------------------------------
var deploymentSuffix = '-${runDateTime}'

// --------------------------------------------------------------------------------
module resourceNames 'resourcenames.bicep' = {
  name: 'resourcenames${deploymentSuffix}'
  params: {
    orgPrefix: orgPrefix
    appPrefix: appPrefix
    environment: environmentCode
    appSuffix: appSuffix
  }
}

// --------------------------------------------------------------------------------
module logAnalyticsModule 'br/public:avm/res/operational-insights/workspace:0.6.0'= {
  name:'loganalytics${deploymentSuffix}'
  params:{
    name: resourceNames.outputs.logAnalyticsWorkspaceName
    location: location
  }
}

module appInsitesModule 'br/public:avm/res/insights/component:0.4.1' = { 
  name: 'appinsites${deploymentSuffix}'
  params: {
    name: resourceNames.outputs.webSiteAppInsightsName
    workspaceResourceId: logAnalyticsModule.outputs.logAnalyticsWorkspaceId
  }
}
