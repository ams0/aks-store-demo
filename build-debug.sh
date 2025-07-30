#!/bin/bash

# Debug version of build-dapr-images.sh
# This version adds extra debugging output

echo "=== DEBUG: Script starting ==="
echo "=== DEBUG: PWD: $(pwd) ==="
echo "=== DEBUG: Parameters: $@ ==="

set -e

REGISTRY=${1:-"daprdemo.azurecr.io"}
PROJECT=${2:-"aks-store-demo"}
VERSION=${3:-"dapr-latest"}

echo "=== DEBUG: Variables set ==="
echo "REGISTRY=$REGISTRY"
echo "PROJECT=$PROJECT" 
echo "VERSION=$VERSION"

echo ""
echo "🚀 Building and pushing Dapr-enabled images"
echo "📦 Registry: $REGISTRY"
echo "📁 Project: $PROJECT" 
echo "🏷️  Version: $VERSION"
echo ""

# Function to build and push image
build_and_push() {
    local service=$1
    local dockerfile=${2:-"Dockerfile"}
    
    echo "=== DEBUG: Function called for $service ==="
    echo "Building $service..."
    
    if [ ! -d "src/$service" ]; then
        echo "❌ ERROR: Directory src/$service does not exist"
        return 1
    fi
    
    cd src/$service
    echo "=== DEBUG: Changed to $(pwd) ==="
    
    if [ ! -f "$dockerfile" ]; then
        echo "❌ ERROR: Dockerfile $dockerfile does not exist"
        cd ../..
        return 1
    fi
    
    echo "=== DEBUG: About to run docker build ==="
    docker build --build-arg APP_VERSION=$VERSION -f $dockerfile -t ${REGISTRY}/${PROJECT}/${service}:$VERSION .
    
    if [ $? -eq 0 ]; then
        echo "✅ $service built successfully"
        
        echo "=== DEBUG: About to push ==="
        echo "Pushing $service..."
        docker push ${REGISTRY}/${PROJECT}/${service}:$VERSION
        if [ $? -eq 0 ]; then
            echo "✅ $service pushed successfully"
        else
            echo "❌ Failed to push $service"
            cd ../..
            exit 1
        fi
    else
        echo "❌ Failed to build $service"
        cd ../..
        exit 1
    fi
    
    cd ../..
    echo "=== DEBUG: Back to $(pwd) ==="
    echo ""
}

# Test with just one service first
echo "🔧 Building first service for testing..."
build_and_push "order-service"

echo "=== DEBUG: Script completed one service ==="
