# Dapr Deployment Guide for AKS Store Demo

This guide explains how to deploy the AKS Store Demo with Dapr integration, starting with in-cluster services and then migrating to Azure services.

## Prerequisites

1. **AKS Cluster with Dapr installed**

   ```bash
   # Install Dapr on your AKS cluster
   dapr init -k --wait

   # Verify Dapr installation
   dapr status -k
   ```

2. **Enable Dapr injection on namespace**

   ```bash
   kubectl label namespace default dapr-injection=enabled
   ```

3. **Optional: Install Zipkin for distributed tracing**
   ```bash
   kubectl create deployment zipkin --image openzipkin/zipkin
   kubectl expose deployment zipkin --type ClusterIP --port 9411
   ```

## Phase 1: Deploy with In-Cluster Services

### Step 1: Deploy the Dapr-enabled application

```bash
# Deploy the complete application with Dapr sidecars
kubectl apply -f aks-store-all-in-one-dapr.yaml

# Wait for all pods to be ready
kubectl wait --for=condition=Ready pod --all --timeout=300s
```

### Step 2: Verify Dapr components

```bash
# Check Dapr components
dapr components -k

# Expected output:
# NAME           TYPE              AGE  CREATED
# order-pub-sub  pubsub.rabbitmq   30s  2024-01-15 10:30:00
# order-store    state.mongodb     30s  2024-01-15 10:30:00
# product-store  state.mongodb     30s  2024-01-15 10:30:00
```

### Step 3: Test the application

```bash
# Get the store-front external IP
kubectl get service store-front

# Access the application
# Use the EXTERNAL-IP from the previous command
curl http://<EXTERNAL-IP>/api/products
```

### Step 4: Monitor with Dapr Dashboard (Optional)

```bash
# Install Dapr Dashboard
dapr dashboard -k -p 8080

# Access dashboard at http://localhost:8080
```

## Phase 2: Migrate to Azure Services

### Step 1: Create Azure Resources

#### Create Azure Service Bus

```bash
# Create resource group
az group create --name aks-store-dapr-rg --location eastus

# Create Service Bus namespace
az servicebus namespace create \
  --resource-group aks-store-dapr-rg \
  --name aks-store-sb-namespace \
  --location eastus \
  --sku Standard

# Create topic for orders
az servicebus topic create \
  --resource-group aks-store-dapr-rg \
  --namespace-name aks-store-sb-namespace \
  --name orders

# Get connection string
az servicebus namespace authorization-rule keys list \
  --resource-group aks-store-dapr-rg \
  --namespace-name aks-store-sb-namespace \
  --name RootManageSharedAccessKey \
  --query primaryConnectionString -o tsv
```

#### Create Azure Cosmos DB

```bash
# Create Cosmos DB account
az cosmosdb create \
  --resource-group aks-store-dapr-rg \
  --name aks-store-cosmosdb \
  --kind MongoDB \
  --locations regionName=eastus failoverPriority=0 isZoneRedundant=False

# Create databases
az cosmosdb mongodb database create \
  --account-name aks-store-cosmosdb \
  --resource-group aks-store-dapr-rg \
  --name orderdb

az cosmosdb mongodb database create \
  --account-name aks-store-cosmosdb \
  --resource-group aks-store-dapr-rg \
  --name productdb

# Create collections
az cosmosdb mongodb collection create \
  --account-name aks-store-cosmosdb \
  --resource-group aks-store-dapr-rg \
  --database-name orderdb \
  --name orders

az cosmosdb mongodb collection create \
  --account-name aks-store-cosmosdb \
  --resource-group aks-store-dapr-rg \
  --database-name productdb \
  --name products

# Get connection details
az cosmosdb show \
  --resource-group aks-store-dapr-rg \
  --name aks-store-cosmosdb \
  --query documentEndpoint -o tsv

az cosmosdb keys list \
  --resource-group aks-store-dapr-rg \
  --name aks-store-cosmosdb \
  --query primaryMasterKey -o tsv
```

#### Create Azure Key Vault (Optional)

```bash
# Create Key Vault
az keyvault create \
  --resource-group aks-store-dapr-rg \
  --name aks-store-keyvault \
  --location eastus

# Store secrets in Key Vault
az keyvault secret set \
  --vault-name aks-store-keyvault \
  --name "servicebus-connectionstring" \
  --value "<YOUR-SERVICE-BUS-CONNECTION-STRING>"

az keyvault secret set \
  --vault-name aks-store-keyvault \
  --name "cosmosdb-masterkey" \
  --value "<YOUR-COSMOS-DB-MASTER-KEY>"
```

### Step 2: Update Kubernetes Secrets

```bash
# Create secrets with your Azure service connection strings
kubectl create secret generic azure-servicebus-secret \
  --from-literal=connectionstring="<YOUR-SERVICE-BUS-CONNECTION-STRING>"

kubectl create secret generic azure-cosmosdb-secret \
  --from-literal=masterkey="<YOUR-COSMOS-DB-MASTER-KEY>"
```

### Step 3: Deploy Azure Components

```bash
# Update the dapr-components-azure.yaml with your actual values
# Then apply the Azure components
kubectl apply -f dapr-components-azure.yaml

# The application code remains unchanged - Dapr handles the backend switch
```

### Step 4: Remove In-Cluster Services (Optional)

```bash
# Remove MongoDB and RabbitMQ StatefulSets
kubectl delete statefulset mongodb rabbitmq
kubectl delete service mongodb rabbitmq
kubectl delete configmap rabbitmq-enabled-plugins

# Remove the old Dapr components (they are replaced by Azure components)
# This happens automatically when you apply the Azure components with the same names
```

## Monitoring and Observability

### Distributed Tracing

If you installed Zipkin, you can view distributed traces:

```bash
# Port forward to Zipkin
kubectl port-forward deployment/zipkin 9411:9411

# Access Zipkin UI at http://localhost:9411
```

### Dapr Metrics

```bash
# View Dapr metrics (requires Prometheus setup)
kubectl port-forward svc/dapr-prom-prometheus-server 9090:80

# Access Prometheus at http://localhost:9090
```

### Application Logs

```bash
# View application logs (includes Dapr sidecar logs)
kubectl logs -l app=order-service -c order-service
kubectl logs -l app=order-service -c daprd

# View all Dapr sidecar logs
kubectl logs -l app=makeline-service -c daprd
```

## Troubleshooting

### Common Issues

1. **Pods not starting with Dapr injection**

   ```bash
   # Check if namespace has Dapr injection enabled
   kubectl get namespace default --show-labels

   # Enable Dapr injection if needed
   kubectl label namespace default dapr-injection=enabled
   ```

2. **Dapr components not loading**

   ```bash
   # Check component status
   dapr components -k

   # Check component logs
   kubectl logs -l app.kubernetes.io/name=dapr-operator -n dapr-system
   ```

3. **Service invocation not working**

   ```bash
   # Check if services are registered with Dapr
   kubectl exec -it <pod-name> -c daprd -- /daprd --help

   # Test service invocation manually
   kubectl exec -it <pod-name> -- curl http://localhost:3500/v1.0/invoke/product-service/method/health
   ```

4. **Pub/Sub messages not being delivered**

   ```bash
   # Check subscription endpoints
   kubectl logs -l app=makeline-service -c makeline-service

   # Verify Dapr subscription configuration
   kubectl exec -it <makeline-pod> -- curl http://localhost:3500/dapr/subscribe
   ```

## Code Changes Required

### For Full Dapr Integration

The current deployment assumes the existing application code. For full Dapr integration, you would need:

1. **Order Service**: Replace direct RabbitMQ publishing with Dapr pub/sub API
2. **Makeline Service**: Replace queue polling with Dapr subscription endpoints
3. **All Services**: Replace direct database access with Dapr state store API
4. **Frontend Services**: Update proxy configurations to use Dapr service invocation

Refer to the `DAPR.md` file for detailed code change examples.

## Benefits Achieved

With this Dapr deployment:

- ✅ **Service Discovery**: Automatic service-to-service communication
- ✅ **Observability**: Built-in distributed tracing and metrics
- ✅ **Resilience**: Retry policies and circuit breakers
- ✅ **Portability**: Easy migration between cloud providers
- ✅ **Security**: Encrypted service-to-service communication
- ✅ **Configuration**: Centralized component management

## Next Steps

1. **Performance Testing**: Compare performance with and without Dapr
2. **Security Hardening**: Implement mTLS and access control policies
3. **Scaling**: Test horizontal pod autoscaling with Dapr sidecars
4. **Multi-Environment**: Create separate component configurations for dev/staging/prod
