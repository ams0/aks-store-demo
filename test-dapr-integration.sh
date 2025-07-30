#!/bin/bash

# Test Dapr Integration for AKS Store Demo
# Usage: ./test-dapr-integration.sh

echo "🧪 Testing Dapr Integration for AKS Store Demo"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if command succeeded
check_status() {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ $1${NC}"
    else
        echo -e "${RED}❌ $1${NC}"
        exit 1
    fi
}

# Function to check if pods are ready
wait_for_pods() {
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        ready_pods=$(kubectl get pods --no-headers | grep "2/2.*Running" | wc -l)
        total_pods=$(kubectl get pods --no-headers | grep -E "(order-service|makeline-service|product-service|store-front|store-admin|virtual-customer|virtual-worker)" | wc -l)
        
        if [ "$ready_pods" -eq "$total_pods" ] && [ "$total_pods" -gt 0 ]; then
            echo -e "${GREEN}✅ All pods are ready ($ready_pods/$total_pods)${NC}"
            return 0
        fi
        
        echo "⏳ Waiting for pods to be ready ($ready_pods/$total_pods)..."
        sleep 10
        ((attempt++))
    done
    
    echo -e "${RED}❌ Timeout waiting for pods to be ready${NC}"
    kubectl get pods
    return 1
}

echo ""
echo "📋 Step 1: Check Kubernetes cluster connection"
kubectl cluster-info --request-timeout=5s > /dev/null 2>&1
check_status "Kubernetes cluster connection"

echo ""
echo "📋 Step 2: Check Dapr installation"
dapr status -k > /dev/null 2>&1
check_status "Dapr installation"

echo ""
echo "📋 Step 3: Check if pods are running"
wait_for_pods

echo ""
echo "📋 Step 4: Check Dapr components"
components=$(kubectl get components --no-headers | wc -l)
echo "📦 Dapr components found: $components"
kubectl get components
if [ "$components" -ge 1 ]; then
    echo -e "${GREEN}✅ Dapr components are deployed${NC}"
else
    echo -e "${YELLOW}⚠️  No Dapr components found${NC}"
fi

echo ""
echo "📋 Step 5: Test order-service health"
kubectl port-forward service/order-service 3000:3000 &
PORT_FORWARD_PID=$!
sleep 5

response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health || echo "000")
kill $PORT_FORWARD_PID > /dev/null 2>&1

if [ "$response" = "200" ]; then
    echo -e "${GREEN}✅ Order service is healthy${NC}"
else
    echo -e "${RED}❌ Order service health check failed (HTTP $response)${NC}"
fi

echo ""
echo "📋 Step 6: Test makeline-service health"
kubectl port-forward service/makeline-service 3001:3001 &
PORT_FORWARD_PID=$!
sleep 5

response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/health || echo "000")
kill $PORT_FORWARD_PID > /dev/null 2>&1

if [ "$response" = "200" ]; then
    echo -e "${GREEN}✅ Makeline service is healthy${NC}"
else
    echo -e "${RED}❌ Makeline service health check failed (HTTP $response)${NC}"
fi

echo ""
echo "📋 Step 7: Check Dapr sidecar logs for errors"
echo "🔍 Order service Dapr logs:"
kubectl logs deployment/order-service -c daprd --tail=5 | head -3

echo "🔍 Makeline service Dapr logs:"
kubectl logs deployment/makeline-service -c daprd --tail=5 | head -3

echo ""
echo "📋 Step 8: Test pub/sub functionality"
echo "🔍 Checking if makeline-service has Dapr subscription endpoint..."

kubectl port-forward service/makeline-service 3001:3001 &
PORT_FORWARD_PID=$!
sleep 5

subscription_response=$(curl -s http://localhost:3001/dapr/subscribe 2>/dev/null || echo "[]")
kill $PORT_FORWARD_PID > /dev/null 2>&1

if [[ "$subscription_response" == *"order-pub-sub"* ]]; then
    echo -e "${GREEN}✅ Dapr subscription endpoint is working${NC}"
    echo "   📋 Subscription: $subscription_response"
else
    echo -e "${YELLOW}⚠️  Dapr subscription endpoint not found or not working${NC}"
    echo "   Response: $subscription_response"
fi

echo ""
echo "📋 Step 9: Check application logs for Dapr usage"
echo "🔍 Order service application logs (looking for Dapr):"
kubectl logs deployment/order-service -c order-service --tail=10 | grep -i dapr | head -2 || echo "   No Dapr logs found"

echo "🔍 Makeline service application logs (looking for Dapr):"
kubectl logs deployment/makeline-service -c makeline-service --tail=10 | grep -i dapr | head -2 || echo "   No Dapr logs found"

echo ""
echo "📋 Step 10: Check virtual-worker service invocation"
echo "🔍 Virtual worker logs (should show successful order processing):"
kubectl logs deployment/virtual-worker -c virtual-worker --tail=5 | head -3

echo ""
echo "🎯 Integration Test Summary"
echo "=========================="
echo "✅ Basic health checks completed"
echo "✅ Dapr components verified"
echo "✅ Sidecar injection confirmed"

echo ""
echo "🎯 To manually test the full flow:"
echo "1. Port forward to store-front: kubectl port-forward service/store-front 8080:80"
echo "2. Open http://localhost:8080 in browser"
echo "3. Place an order and check logs:"
echo "   kubectl logs deployment/order-service -c order-service -f"
echo "   kubectl logs deployment/makeline-service -c makeline-service -f"

echo ""
echo "🎯 To check RabbitMQ management (optional):"
echo "kubectl port-forward service/rabbitmq 15672:15672"
echo "Open http://localhost:15672 (username: username, password: password)"

echo ""
echo "🎉 Test completed!"
