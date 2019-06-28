#!/bin/bash
set -xe

# Download kubectl
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl 
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Download kind
curl -Lo kind https://github.com/kubernetes-sigs/kind/releases/download/v0.4.0/kind-linux-amd64
chmod +x kind 
sudo mv kind /usr/local/bin/

# Create kind cluster
kind create cluster
export KUBECONFIG="$(kind get kubeconfig-path)"

# Build docker image from students Dockerfile
docker build kubernetes-intro/web/ -t web:homework-1

# Move docker image to kine node
kind load docker-image web:homework-1

# Create pod from students manifest
kubectl set image web=web:homework-1 --local -f kubernetes-intro/web-pod.yaml -o yaml | kubectl apply -f -

# Debug
kubectl describe pod web
docker exec kind-control-plane ctr --namespace k8s.io images list

# Wait while pod is running
kubectl wait --for=condition=Ready pod/web --timeout=120s

# Forward 8000 port to host, check availability
kubectl port-forward pod/web 8000:8000 &
curl -sSf localhost:8000 -o /dev/null