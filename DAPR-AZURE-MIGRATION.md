# Dapr Components Migration Guide: Local → Azure Services

This guide explains how to migrate from in-cluster MongoDB and RabbitMQ to Azure-hosted services.

## Components Comparison

### Pub/Sub Component (`order-pub-sub`)

#### Before (Local - RabbitMQ)
```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: order-pub-sub
spec:
  type: pubsub.rabbitmq
  metadata:
    - name: host
      value: "amqp://username:password@rabbitmq:5672"
```

#### After (Azure Service Bus)
```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: order-pub-sub
spec:
  type: pubsub.azure.servicebus
  metadata:
    - name: connectionString
      secretKeyRef:
        name: azure-servicebus-secret
        key: connectionstring
```

### State Store Component (`order-store`)

#### Before (Local - MongoDB)
```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: order-store
spec:
  type: state.mongodb
  metadata:
    - name: host
      value: "mongodb:27017"
    - name: databaseName
      value: "orderdb"
```

#### After (Azure Cosmos DB)
```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: order-store
spec:
  type: state.azure.cosmosdb
  metadata:
    - name: url
      value: "https://your-cosmosdb-account.documents.azure.com:443/"
    - name: masterKey
      secretKeyRef:
        name: azure-cosmosdb-secret
        key: masterkey
    - name: database
      value: "orderdb"
    - name: collection
      value: "orders"
```

## Azure Services Required

### 1. Azure Service Bus
- **Resource**: Service Bus Namespace (Standard tier)
- **Purpose**: Replaces RabbitMQ for pub/sub messaging
- **Features**:
  - Topics and subscriptions for message routing
  - Built-in dead letter queues
  - Message sessions and ordering
  - Integration with Azure monitoring

### 2. Azure Cosmos DB
- **Resource**: Cosmos DB Account with SQL API
- **Purpose**: Replaces MongoDB for state storage
- **Features**:
  - Global distribution
  - Multiple consistency levels
  - Automatic scaling
  - SLA-backed performance

## Migration Steps

### 1. Deploy Azure Services
```bash
# Set environment variables
export AZURE_RESOURCE_GROUP="aks-store-dapr-rg"
export AZURE_LOCATION="eastus"
export AZURE_ENV_NAME="dev"

# Run the deployment script
./deploy-azure-dapr-services.sh
```

### 2. Update Application Deployment
The deployment script automatically updates `dapr-components-azure.yaml` with the actual connection strings and applies the components to Kubernetes.

### 3. Switch Component Files
Replace the local components with Azure components:
```bash
# Backup current components
kubectl get components -o yaml > dapr-components-backup.yaml

# Apply Azure components
kubectl apply -f dapr-components-azure.yaml

# Remove local components (MongoDB/RabbitMQ deployments)
# Keep them running during testing, remove after validation
```

### 4. Verify Migration
```bash
# Check component status
kubectl get components

# Verify Dapr sidecars can connect
kubectl logs -l app=order-service -c daprd
kubectl logs -l app=makeline-service -c daprd

# Test the complete workflow
kubectl apply -f aks-store-all-in-one-dapr-custom.yaml
```

## Benefits of Azure Services

### Service Bus vs RabbitMQ
- ✅ Managed service (no maintenance overhead)
- ✅ Built-in high availability and disaster recovery
- ✅ Integration with Azure Monitor and alerts
- ✅ Enterprise-grade security and compliance
- ✅ Automatic scaling based on load

### Cosmos DB vs MongoDB
- ✅ Global distribution with single-digit millisecond latency
- ✅ Multiple consistency models to choose from
- ✅ Automatic and instant scaling
- ✅ 99.999% availability SLA
- ✅ Multiple APIs (SQL, MongoDB, Cassandra, etc.)
- ✅ Built-in analytics with Azure Synapse Link

## Cost Considerations

### Service Bus
- **Standard Tier**: ~$10/month base + $0.05 per million operations
- **Premium Tier**: ~$675/month with dedicated capacity

### Cosmos DB
- **Serverless**: Pay per request (good for dev/test)
- **Provisioned**: Starting at ~$24/month for 400 RU/s
- **Free Tier**: 1000 RU/s and 25 GB storage free

## Security Best Practices

1. **Use Managed Identity** (recommended for production):
   - Eliminates need for connection strings
   - Automatic credential rotation
   - Granular RBAC permissions

2. **Key Vault Integration**:
   - Store connection strings in Azure Key Vault
   - Use Key Vault CSI driver for automatic secret mounting

3. **Network Security**:
   - Configure virtual network service endpoints
   - Use private endpoints for enhanced security

## Troubleshooting

### Common Issues
1. **Component not loading**: Check secret base64 encoding
2. **Authentication failures**: Verify connection strings and permissions
3. **Network connectivity**: Ensure AKS can reach Azure services
4. **Performance issues**: Monitor RU consumption in Cosmos DB

### Monitoring
- Use Azure Monitor for service health and metrics
- Enable Dapr tracing for end-to-end visibility
- Set up alerts for service degradation
