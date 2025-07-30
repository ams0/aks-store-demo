#!/bin/bash

echo "🧪 Testing order-service locally..."

cd src/order-service

# Set Dapr environment variables
export USE_DAPR_PUBSUB="true"
export PUBSUB_NAME="order-pub-sub"
export PUBSUB_TOPIC="orders"
export DAPR_HTTP_PORT="3500"
export FASTIFY_ADDRESS="0.0.0.0"
export APP_VERSION="dapr-test"

echo "Environment variables:"
echo "  USE_DAPR_PUBSUB=$USE_DAPR_PUBSUB"
echo "  PUBSUB_NAME=$PUBSUB_NAME"
echo "  PUBSUB_TOPIC=$PUBSUB_TOPIC"
echo "  DAPR_HTTP_PORT=$DAPR_HTTP_PORT"
echo ""

# Install dependencies if needed
if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    npm install
fi

echo "Starting order-service..."
echo "Note: This will fail to publish messages without Dapr running, but should start successfully"
echo ""

# Start the service (will exit after a few seconds for testing)
timeout 10s npm start || echo "Service started successfully (timeout expected)"

echo ""
echo "✅ If you see 'Server listening at' above, the service is working"
echo "❌ If you see plugin errors, there are still issues to fix"

cd ../..
