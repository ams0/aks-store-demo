# Dapr Pub/Sub Integration Guide

This guide explains how to convert the AKS Store Demo from direct RabbitMQ connections to Dapr pub/sub abstraction.

## 🔄 **Conversion Summary**

### **Before (Direct RabbitMQ)**

```javascript
// Order Service - Publishing
const amqp = require("amqplib")
const connection = await amqp.connect("amqp://username:password@rabbitmq:5672")
const channel = await connection.createChannel()
await channel.assertQueue("orders")
channel.sendToQueue("orders", Buffer.from(JSON.stringify(order)))
```

```go
// Makeline Service - Consuming
conn, err := amqp.Dial("amqp://username:password@rabbitmq:5672")
channel, err := conn.Channel()
msgs, err := channel.Consume("orders", "", false, false, false, false, nil)
```

### **After (Dapr Pub/Sub)**

```javascript
// Order Service - Publishing via Dapr HTTP API
const axios = require("axios")
await axios.post("http://localhost:3500/v1.0/publish/order-pub-sub/orders", order)
```

```go
// Makeline Service - Subscribing via Dapr HTTP endpoint
// GET /dapr/subscribe returns subscription metadata
// POST /orders handles incoming messages from Dapr
```

## 📋 **Key Changes in the Manifest**

### **1. Environment Variables Changed**

**Order Service:**

```yaml
# REMOVED: Direct RabbitMQ config
# - name: ORDER_QUEUE_HOSTNAME
#   value: "rabbitmq"
# - name: ORDER_QUEUE_PORT
#   value: "5672"

# ADDED: Dapr pub/sub config
- name: USE_DAPR_PUBSUB
  value: "true"
- name: PUBSUB_NAME
  value: "order-pub-sub"
- name: DAPR_HTTP_PORT
  value: "3500"
```

**Makeline Service:**

```yaml
# REMOVED: Direct connections
# - name: ORDER_QUEUE_URI
#   value: "amqp://rabbitmq:5672"
# - name: ORDER_DB_URI
#   value: "mongodb://mongodb:27017"

# ADDED: Dapr components
- name: USE_DAPR_PUBSUB
  value: "true"
- name: USE_DAPR_STATE_STORE
  value: "true"
- name: STATE_STORE_NAME
  value: "order-store"
```

### **2. Init Containers Removed**

```yaml
# REMOVED: No longer need to wait for RabbitMQ directly
# initContainers:
#   - name: wait-for-rabbitmq
#     image: busybox
#     command: ["sh", "-c", "until nc -zv rabbitmq 5672; do echo waiting for rabbitmq; sleep 2; done;"]
```

### **3. Added State Store Component**

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

## 🔧 **Required Application Code Changes**

### **Order Service (Node.js)**

**Publishing Messages:**

```javascript
// OLD: Direct RabbitMQ
const amqp = require("amqplib")
const connection = await amqp.connect(process.env.ORDER_QUEUE_URI)
// ... channel setup and publishing

// NEW: Dapr HTTP API
const axios = require("axios")
const daprPort = process.env.DAPR_HTTP_PORT || 3500
const pubsubName = process.env.PUBSUB_NAME
const topic = process.env.PUBSUB_TOPIC

await axios.post(`http://localhost:${daprPort}/v1.0/publish/${pubsubName}/${topic}`, orderData)
```

### **Makeline Service (Go)**

**Subscribing to Messages:**

```go
// OLD: Direct AMQP consumption
conn, err := amqp.Dial(orderQueueURI)
// ... channel setup and message handling

// NEW: Dapr subscription endpoints
// 1. Subscription metadata endpoint
func getSubscriptions(w http.ResponseWriter, r *http.Request) {
    subscriptions := []Subscription{
        {
            PubsubName: os.Getenv("PUBSUB_NAME"),
            Topic:      os.Getenv("PUBSUB_TOPIC"),
            Route:      "/orders",
        },
    }
    json.NewEncoder(w).Encode(subscriptions)
}

// 2. Message handler endpoint
func handleOrder(w http.ResponseWriter, r *http.Request) {
    var cloudEvent CloudEvent
    json.NewDecoder(r.Body).Decode(&cloudEvent)
    // Process order from cloudEvent.Data
}

// Register endpoints
router.HandleFunc("/dapr/subscribe", getSubscriptions).Methods("GET")
router.HandleFunc("/orders", handleOrder).Methods("POST")
```

**State Management:**

```go
// OLD: Direct MongoDB
client, err := mongo.Connect(ctx, options.Client().ApplyURI(orderDBURI))
// ... collection operations

// NEW: Dapr State API
daprPort := os.Getenv("DAPR_HTTP_PORT")
stateStoreName := os.Getenv("STATE_STORE_NAME")

// Save state
stateData := []StateRequest{{Key: orderID, Value: order}}
http.Post(fmt.Sprintf("http://localhost:%s/v1.0/state/%s", daprPort, stateStoreName), "application/json", stateData)

// Get state
resp, err := http.Get(fmt.Sprintf("http://localhost:%s/v1.0/state/%s/%s", daprPort, stateStoreName, orderID))
```

## 🎯 **Benefits of This Conversion**

### **1. Cloud Portability**

- Same code works with RabbitMQ locally, Azure Service Bus in cloud
- Switch backing stores by changing Dapr component configuration only

### **2. Simplified Operations**

- No more connection management, retries, or circuit breakers in app code
- Dapr handles resilience, observability, and security

### **3. Polyglot Support**

- Order service (Node.js) and Makeline service (Go) use same HTTP APIs
- No language-specific messaging libraries needed

## 🚀 **Deployment Comparison**

| Feature          | Local (Direct) | Local (Dapr)      | Azure (Dapr)      |
| ---------------- | -------------- | ----------------- | ----------------- |
| **Pub/Sub**      | RabbitMQ       | RabbitMQ via Dapr | Azure Service Bus |
| **State**        | MongoDB        | MongoDB via Dapr  | Azure Cosmos DB   |
| **Code Changes** | None           | Minimal           | None              |
| **Operations**   | Manual         | Dapr managed      | Dapr managed      |

## 📝 **Usage Instructions**

1. **Deploy the new manifest:**

   ```bash
   kubectl apply -f aks-store-all-in-one-dapr-pubsub.yaml
   ```

2. **Verify components:**

   ```bash
   kubectl get components
   # Should show: order-pub-sub, order-store
   ```

3. **Check application logs for Dapr usage:**
   ```bash
   kubectl logs deployment/order-service -c order-service
   kubectl logs deployment/makeline-service -c makeline-service
   ```

**Note:** This manifest requires application code modifications to actually use the Dapr APIs. The current container images still use direct connections, so this serves as a template for the conversion process.
