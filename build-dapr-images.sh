#!/bin/bash

# Build and Push Dapr-enabled images for AKS Store Demo
# Usage: ./build-dapr-images.sh [registry] [project] [version]
# Example: ./build-dapr-images.sh daprdemo.azurecr.io aks-store-demo dapr-latest

set -e

REGISTRY=${1:-"daprdemo.azurecr.io"}
PROJECT=${2:-"aks-store-demo"}
VERSION=${3:-"dapr-latest"}

echo "🚀 Building and pushing Dapr-enabled images"
echo "📦 Registry: $REGISTRY"
echo "📁 Project: $PROJECT" 
echo "🏷️  Version: $VERSION"
echo ""

# Function to build and push image
build_and_push() {
    local service=$1
    local dockerfile=${2:-"Dockerfile"}
    
    echo "Building $service..."
    cd src/$service
    
    docker build --build-arg APP_VERSION=$VERSION -f $dockerfile -t ${REGISTRY}/${PROJECT}/${service}:$VERSION .
    if [ $? -eq 0 ]; then
        echo "✅ $service built successfully"
        
        echo "Pushing $service..."
        docker push ${REGISTRY}/${PROJECT}/${service}:$VERSION
        if [ $? -eq 0 ]; then
            echo "✅ $service pushed successfully"
        else
            echo "❌ Failed to push $service"
            exit 1
        fi
    else
        echo "❌ Failed to build $service"
        exit 1
    fi
    
    cd ../..
    echo ""
}

# Build Dapr-enabled services (custom images with Dapr code)
echo "🔧 Building custom Dapr-enabled services..."
build_and_push "order-service"
build_and_push "makeline-service" "Dockerfile.dapr"

# Build standard services (with Dapr sidecar support)
echo "🏪 Building standard services..."
build_and_push "product-service"
build_and_push "store-front"
build_and_push "store-admin"
build_and_push "virtual-customer"
build_and_push "virtual-worker"

echo "🎉 All images built and pushed successfully!"
echo ""
echo "📋 Images pushed to registry:"
echo "  - ${REGISTRY}/${PROJECT}/order-service:$VERSION"
echo "  - ${REGISTRY}/${PROJECT}/makeline-service:$VERSION"
echo "  - ${REGISTRY}/${PROJECT}/product-service:$VERSION" 
echo "  - ${REGISTRY}/${PROJECT}/store-front:$VERSION"
echo "  - ${REGISTRY}/${PROJECT}/store-admin:$VERSION"
echo "  - ${REGISTRY}/${PROJECT}/virtual-customer:$VERSION"
echo "  - ${REGISTRY}/${PROJECT}/virtual-worker:$VERSION"
echo ""
echo "✅ Ready to deploy with: kubectl apply -f aks-store-all-in-one-dapr-custom.yaml"
