# Adding Dapr to the AKS Store Demo

This document explains the process and reasoning for integrating [Dapr (Distributed Application Runtime)](https://dapr.io) into the AKS Store Demo application.

## Why Add Dapr?

### Current Architecture Challenges

The AKS Store Demo currently implements a microservices architecture with the following communication patterns:

1. **Direct Service-to-Service HTTP Communication**: Web applications (store-front, store-admin) make direct HTTP calls to backend services
2. **Message Queue Integration**: Services directly integrate with RabbitMQ/Azure Service Bus using native SDKs
3. **Database Access**: Services directly connect to MongoDB and other data stores
4. **Configuration Management**: Environment variables scattered across deployments for connection strings and settings

### Benefits of Adding Dapr

Dapr provides several advantages that address common microservices challenges:

#### 1. **Service Invocation Abstraction**

- **Before**: Direct HTTP calls with hardcoded service endpoints
- **After**: Dapr service invocation with automatic service discovery, load balancing, and retry policies

#### 2. **Pub/Sub Abstraction**

- **Before**: Direct RabbitMQ/Azure Service Bus SDK integration requiring connection string management
- **After**: Dapr pub/sub component that abstracts the message broker implementation

#### 3. **State Management**

- **Before**: Direct MongoDB connections with custom data access logic
- **After**: Dapr state store component providing consistent CRUD operations across different databases

#### 4. **Secrets Management**

- **Before**: Environment variables containing sensitive connection strings
- **After**: Dapr secrets component with integration to Azure Key Vault or Kubernetes secrets

#### 5. **Observability**

- **Before**: Custom logging and metrics collection
- **After**: Built-in distributed tracing, metrics, and logging with OpenTelemetry standards

#### 6. **Resiliency**

- **Before**: Custom retry logic and circuit breaker patterns
- **After**: Built-in retry policies, timeouts, and circuit breakers at the Dapr runtime level

## Current Service Communication Patterns

### 1. Order Processing Flow

```
store-front → order-service → RabbitMQ → makeline-service → MongoDB
```

**Current Implementation:**

- `order-service` uses `@azure/service-bus` SDK to publish messages
- `makeline-service` uses `azservicebus` Go SDK to consume messages
- Both services manage connection strings and authentication directly

### 2. Product Management Flow

```
store-admin → product-service → (AI Service) → Database
```

**Current Implementation:**

- Direct HTTP calls from frontend to backend services
- Services expose REST APIs for CRUD operations
- Connection strings managed via environment variables

### 3. Data Persistence

```
makeline-service → MongoDB (orders)
product-service → Database (products)
```

**Current Implementation:**

- Direct database connections using native drivers
- Connection string management via environment variables

## Proposed Dapr Integration

### Phase 1: Service-to-Service Communication

#### 1.1 Service Invocation

Replace direct HTTP calls with Dapr service invocation:

**Before (store-admin calling product-service):**

```javascript
fetch(`${PRODUCT_SERVICE_URL}/products`)
```

**After (using Dapr service invocation):**

```javascript
fetch(`http://localhost:3500/v1.0/invoke/product-service/method/products`)
```

#### 1.2 Benefits

- Automatic service discovery
- Built-in retry policies
- Load balancing across service instances
- Circuit breaker patterns
- Distributed tracing

### Phase 2: Pub/Sub Integration

#### 2.1 Replace Direct Message Queue Access

Transform the order processing flow to use Dapr pub/sub:

**Before (order-service publishing):**

```javascript
// Direct RabbitMQ/Service Bus SDK usage
const { ServiceBusClient } = require("@azure/service-bus")
const client = new ServiceBusClient(connectionString)
const sender = client.createSender(queueName)
await sender.sendMessages(message)
```

**After (Dapr pub/sub):**

```javascript
// Dapr pub/sub API
await fetch("http://localhost:3500/v1.0/publish/order-pub-sub/orders", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(orderData),
})
```

**Before (makeline-service consuming):**

```go
// Direct RabbitMQ/Service Bus SDK usage
receiver, err := client.NewReceiverForQueue(queueName, nil)
messages, err := receiver.ReceiveMessages(ctx, 10, nil)
```

**After (Dapr pub/sub subscription):**

```go
// Dapr subscription endpoint
// Messages delivered via HTTP POST to /orders endpoint
func ordersHandler(w http.ResponseWriter, r *http.Request) {
    // Process incoming order from Dapr
}
```

#### 2.2 Dapr Component Configuration

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: order-pub-sub
spec:
  type: pubsub.rabbitmq
  version: v1
  metadata:
    - name: host
      value: "amqp://rabbitmq:5672"
    - name: username
      value: "username"
    - name: password
      value: "password"
```

### Phase 3: State Management

#### 3.1 Replace Direct Database Access

Transform data persistence to use Dapr state store:

**Before (makeline-service MongoDB access):**

```go
// Direct MongoDB driver usage
collection := client.Database("orderdb").Collection("orders")
result, err := collection.InsertOne(ctx, order)
```

**After (Dapr state store):**

```go
// Dapr state store API
stateData := []map[string]interface{}{
    {
        "key": orderID,
        "value": order,
    },
}
jsonData, _ := json.Marshal(stateData)
resp, err := http.Post("http://localhost:3500/v1.0/state/order-store",
    "application/json", bytes.NewBuffer(jsonData))
```

#### 3.2 Dapr State Store Component

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: order-store
spec:
  type: state.mongodb
  version: v1
  metadata:
    - name: host
      value: "mongodb://mongodb:27017"
    - name: databaseName
      value: "orderdb"
    - name: collectionName
      value: "orders"
```

### Phase 4: Secrets Management

#### 4.1 Centralize Secret Management

Replace environment variable-based configuration:

**Before:**

```yaml
env:
  - name: ORDER_QUEUE_USERNAME
    value: "username"
  - name: ORDER_QUEUE_PASSWORD
    value: "password"
  - name: ORDER_DB_URI
    value: "mongodb://mongodb:27017"
```

**After (using Dapr secrets):**

```yaml
# Dapr secrets component references Azure Key Vault or K8s secrets
# Services retrieve secrets via Dapr API
```

#### 4.2 Dapr Secrets Component

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: app-secrets
spec:
  type: secretstores.kubernetes
  version: v1
```

## Implementation Plan

### Step 1: Environment Preparation

1. **Install Dapr on AKS cluster**

   ```bash
   dapr init -k --wait
   ```

2. **Enable Dapr on namespace**

   ```bash
   kubectl label namespace default dapr-injection=enabled
   ```

### Step 2: Service Invocation (Week 1)

1. **Update store-front to use Dapr service invocation**

   - Replace direct API calls with Dapr invoke API
   - Update nginx configuration if needed

2. **Update store-admin to use Dapr service invocation**

   - Replace direct API calls with Dapr invoke API
   - Update build-time proxy configuration

3. **Add Dapr sidecars to deployments**
   - Add Dapr annotations to Kubernetes deployments
   - Configure Dapr app-id for each service

### Step 3: Pub/Sub Integration (Week 2)

1. **Create Dapr pub/sub component**

   - Configure RabbitMQ/Azure Service Bus component
   - Apply component to cluster

2. **Update order-service**

   - Replace direct queue publishing with Dapr pub/sub API
   - Remove direct RabbitMQ/Service Bus SDK dependencies

3. **Update makeline-service**
   - Replace queue polling with Dapr subscription endpoint
   - Configure subscription metadata

### Step 4: State Management (Week 3)

1. **Create Dapr state store components**

   - Configure MongoDB state store for orders
   - Configure additional state stores as needed

2. **Update services to use Dapr state API**
   - Replace direct database calls
   - Implement state operations (get, set, delete)

### Step 5: Secrets Management (Week 4)

1. **Create Dapr secrets component**

   - Configure Kubernetes secrets or Azure Key Vault
   - Migrate sensitive configuration

2. **Update component configurations**
   - Reference secrets in Dapr components
   - Remove hardcoded credentials

### Step 6: Observability Enhancement (Week 5)

1. **Configure distributed tracing**

   - Set up Jaeger or Zipkin
   - Configure trace sampling

2. **Set up metrics collection**
   - Configure Prometheus metrics
   - Create Grafana dashboards

## Dapr Component Configurations

### 1. Pub/Sub Component (RabbitMQ)

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: order-pub-sub
  namespace: default
spec:
  type: pubsub.rabbitmq
  version: v1
  metadata:
    - name: host
      value: "amqp://rabbitmq:5672"
    - name: username
      secretKeyRef:
        name: rabbitmq-secret
        key: username
    - name: password
      secretKeyRef:
        name: rabbitmq-secret
        key: password
    - name: durable
      value: "true"
scopes:
  - order-service
  - makeline-service
```

### 2. State Store Component (MongoDB)

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: order-store
  namespace: default
spec:
  type: state.mongodb
  version: v1
  metadata:
    - name: host
      value: "mongodb://mongodb:27017"
    - name: databaseName
      value: "orderdb"
    - name: collectionName
      value: "orders"
scopes:
  - makeline-service
```

### 3. Secrets Component (Kubernetes)

```yaml
apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: app-secrets
  namespace: default
spec:
  type: secretstores.kubernetes
  version: v1
scopes:
  - order-service
  - makeline-service
  - product-service
```

## Deployment Changes

### Service Deployment Updates

Each service deployment needs Dapr annotations:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
spec:
  template:
    metadata:
      labels:
        app: order-service
      annotations:
        dapr.io/enabled: "true"
        dapr.io/app-id: "order-service"
        dapr.io/app-port: "3000"
        dapr.io/log-level: "info"
        dapr.io/enable-metrics: "true"
        dapr.io/metrics-port: "9090"
    spec:
      containers:
        - name: order-service
          image: ghcr.io/azure-samples/aks-store-demo/order-service:latest
          ports:
            - containerPort: 3000
          # Remove queue-specific environment variables
          # Keep only app-specific configuration
```

## Code Changes Summary

### 1. Order Service (Node.js)

**Files to modify:**

- `src/order-service/plugins/messagequeue.js` - Replace with Dapr pub/sub
- `src/order-service/package.json` - Remove message queue SDKs

**New approach:**

```javascript
// Replace queue publishing with Dapr API call
async function publishOrder(order) {
  const response = await fetch("http://localhost:3500/v1.0/publish/order-pub-sub/orders", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(order),
  })

  if (!response.ok) {
    throw new Error("Failed to publish order")
  }
}
```

### 2. Makeline Service (Go)

**Files to modify:**

- `src/makeline-service/orderqueue.go` - Replace with subscription endpoint
- `src/makeline-service/main.go` - Add HTTP handler for subscriptions
- `src/makeline-service/go.mod` - Remove Azure Service Bus SDK

**New approach:**

```go
// Add subscription endpoint
func subscriptionHandler(w http.ResponseWriter, r *http.Request) {
    var order Order
    if err := json.NewDecoder(r.Body).Decode(&order); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    // Process order using existing logic
    processOrder(order)

    // Return success to Dapr
    w.WriteHeader(http.StatusOK)
}

// Add subscription configuration endpoint
func daprSubscriptions(w http.ResponseWriter, r *http.Request) {
    subscriptions := []map[string]interface{}{
        {
            "pubsubname": "order-pub-sub",
            "topic":      "orders",
            "route":      "/orders",
        },
    }

    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(subscriptions)
}
```

### 3. Frontend Services (Vue.js)

**Files to modify:**

- `src/store-front/nginx.conf` - Update proxy rules for Dapr
- `src/store-admin/nginx.conf` - Update proxy rules for Dapr

**New approach:**

```nginx
# Proxy API calls through Dapr sidecar
location /api/products {
    proxy_pass http://localhost:3500/v1.0/invoke/product-service/method/products;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}

location /api/orders {
    proxy_pass http://localhost:3500/v1.0/invoke/order-service/method/orders;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

## Testing Strategy

### 1. Unit Testing

- Mock Dapr API endpoints in service tests
- Test component configuration validation
- Verify subscription handling logic

### 2. Integration Testing

- Test service-to-service communication via Dapr
- Verify pub/sub message flow
- Test state persistence operations

### 3. End-to-End Testing

- Deploy full application with Dapr components
- Test complete order processing workflow
- Verify observability and monitoring

## Monitoring and Observability

### 1. Distributed Tracing

Dapr automatically generates traces for:

- Service invocations
- Pub/sub operations
- State store operations

### 2. Metrics Collection

Built-in metrics for:

- Request latency and throughput
- Error rates
- Component health

### 3. Logging

Enhanced logging with:

- Correlation IDs
- Service topology information
- Component-specific logs

## Migration Strategy

### Phase 1: Parallel Implementation

- Keep existing implementation running
- Add Dapr components alongside current architecture
- Implement feature flags to switch between approaches

### Phase 2: Gradual Migration

- Start with service invocation (lowest risk)
- Move to pub/sub integration
- Finally migrate state management

### Phase 3: Cleanup

- Remove old SDKs and dependencies
- Clean up environment variables
- Update documentation

## Benefits Realized

After completing the Dapr integration:

1. **Reduced Complexity**: Less boilerplate code for infrastructure concerns
2. **Improved Portability**: Easier to switch between cloud providers or deployment environments
3. **Enhanced Observability**: Built-in tracing and metrics without custom implementation
4. **Better Resilience**: Automatic retry policies and circuit breakers
5. **Simplified Configuration**: Centralized component management
6. **Security**: Better secrets management and service-to-service communication

## Conclusion

Adding Dapr to the AKS Store Demo transforms it from a collection of loosely coupled microservices into a modern, cloud-native application following best practices for distributed systems. The migration provides immediate benefits in terms of operational complexity reduction while preparing the application for future scale and multi-cloud deployment scenarios.

The phased approach ensures minimal disruption to the existing functionality while providing clear value at each step of the implementation.
