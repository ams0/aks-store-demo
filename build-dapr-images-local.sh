#!/bin/bash

# Build Dapr-enabled images locally (without pushing)
# Usage: ./build-dapr-images-local.sh [version]
# Example: ./build-dapr-images-local.sh dapr-latest

set -e

VERSION=${1:-"dapr-latest"}

echo "🚀 Building Dapr-enabled images locally"
echo "🏷️  Version: $VERSION"
echo ""

# Function to build image locally
build_local() {
    local service=$1
    local dockerfile=${2:-"Dockerfile"}
    
    echo "Building $service..."
    cd src/$service
    
    docker build --build-arg APP_VERSION=$VERSION -f $dockerfile -t aks-store-demo-${service}:$VERSION .
    if [ $? -eq 0 ]; then
        echo "✅ $service built successfully"
    else
        echo "❌ Failed to build $service"
        exit 1
    fi
    
    cd ../..
    echo ""
}

# Build Dapr-enabled services (custom images with Dapr code)
echo "🔧 Building custom Dapr-enabled services..."
build_local "order-service"
build_local "makeline-service" "Dockerfile.dapr"

# Build standard services (with Dapr sidecar support)
echo "🏪 Building standard services..."
build_local "product-service"
build_local "store-front"
build_local "store-admin"
build_local "virtual-customer"
build_local "virtual-worker"

echo "🎉 All images built successfully!"
echo ""
echo "📋 Local images built:"
echo "  - aks-store-demo-order-service:$VERSION"
echo "  - aks-store-demo-makeline-service:$VERSION"
echo "  - aks-store-demo-product-service:$VERSION" 
echo "  - aks-store-demo-store-front:$VERSION"
echo "  - aks-store-demo-store-admin:$VERSION"
echo "  - aks-store-demo-virtual-customer:$VERSION"
echo "  - aks-store-demo-virtual-worker:$VERSION"
echo ""
echo "🚀 To push to registry, use: ./build-dapr-images.sh [registry] [project] [version]"
