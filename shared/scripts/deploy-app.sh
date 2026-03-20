#!/bin/bash
set -e
CLUSTER=${1:?Usage: $0 <cluster-name> <region>}
REGION=${2:-us-west-2}

echo "=== Deploying sample app to EKS cluster: $CLUSTER in $REGION ==="
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER"

# Create namespace
kubectl create namespace dr-lab --dry-run=client -o yaml | kubectl apply -f -

# Deploy sample nginx app with health check
cat <<'K8S' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  namespace: dr-lab
  labels:
    app: sample-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
    spec:
      containers:
      - name: nginx
        image: public.ecr.aws/nginx/nginx:latest
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 15
          periodSeconds: 20
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: sample-app
  namespace: dr-lab
spec:
  type: ClusterIP
  selector:
    app: sample-app
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sample-app
  namespace: dr-lab
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: sample-app
            port:
              number: 80
K8S

echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=sample-app -n dr-lab --timeout=120s
echo "=== Deployment complete ==="
kubectl get all -n dr-lab
