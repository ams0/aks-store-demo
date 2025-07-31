// Azure Services for Dapr Components
// This Bicep template creates Azure Service Bus and Cosmos DB to replace in-cluster RabbitMQ and MongoDB

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
param environmentName string = 'dev'

@description('Resource token for unique naming')
param resourceToken string = uniqueString(resourceGroup().id)

// Service Bus Namespace
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: 'sb-aks-store-${environmentName}-${resourceToken}'
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
  tags: {
    'azd-env-name': environmentName
    purpose: 'dapr-pubsub'
  }
}

// Service Bus Topic for order events
resource orderTopic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'orders'
  properties: {
    maxMessageSizeInKilobytes: 256
    defaultMessageTimeToLive: 'P14D'
    maxSizeInMegabytes: 1024
    requiresDuplicateDetection: false
    enableBatchedOperations: true
    supportOrdering: false
    autoDeleteOnIdle: 'P10675199DT2H48M5.4775807S'
    enablePartitioning: false
    enableExpress: false
  }
}

// Service Bus Authorization Rule for Dapr
resource serviceBusAuthRule 'Microsoft.ServiceBus/namespaces/authorizationRules@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'DaprAccessKey'
  properties: {
    rights: [
      'Listen'
      'Send'
      'Manage'
    ]
  }
}

// Cosmos DB Account
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: 'cosmos-aks-store-${environmentName}-${resourceToken}'
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    publicNetworkAccess: 'Enabled'
    networkAclBypass: 'AzureServices'
    disableKeyBasedMetadataWriteAccess: false
    enableFreeTier: true
    minimalTlsVersion: 'Tls12'
  }
  tags: {
    'azd-env-name': environmentName
    purpose: 'dapr-state-store'
  }
}

// Cosmos DB Database for orders
resource orderDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  parent: cosmosAccount
  name: 'orderdb'
  properties: {
    resource: {
      id: 'orderdb'
    }
    options: {
      throughput: 400
    }
  }
}

// Cosmos DB Container for orders
resource orderContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: orderDatabase
  name: 'orders'
  properties: {
    resource: {
      id: 'orders'
      partitionKey: {
        paths: [
          '/id'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          {
            path: '/*'
          }
        ]
      }
    }
  }
}

// Outputs for connection strings and configuration
output serviceBusNamespace string = serviceBusNamespace.name
output serviceBusConnectionString string = serviceBusAuthRule.listKeys().primaryConnectionString
output cosmosAccountName string = cosmosAccount.name
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
output cosmosPrimaryKey string = cosmosAccount.listKeys().primaryMasterKey
output resourceGroupName string = resourceGroup().name
