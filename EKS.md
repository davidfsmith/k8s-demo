# EKS Deployment Guide

This document describes how to deploy the Ingress + Observability demo on **Amazon EKS**.

---

## 0) Create a basic EKS cluster

You can create a cluster using `eksctl`:

```bash
eksctl create cluster -f eksctl-cluster.yaml
```

Example quick CLI version:

```bash
eksctl create cluster --name demo-ingress --region eu-west-1   --nodes 2 --node-type m5.large --version 1.30 --with-oidc
```

---

## 1) Install kube-prometheus-stack (creates CRDs)

Install monitoring **before** enabling ServiceMonitor on ingress.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack   -n monitoring --create-namespace

kubectl -n monitoring rollout status deploy/monitoring-grafana --timeout=300s
```

---

## 2) Install ingress-nginx (LoadBalancer + metrics)

Use the version-appropriate values file (v1.12+ shown here).

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx   -n ingress-nginx --create-namespace   --set controller.image.tag=v1.13.3   -f values.v1.12plus.yaml
```

Optional (explicit NLB):

```yaml
# in values file under controller.service.annotations:
service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
# (optional) preserve client IPs:
# service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "instance"
# externalTrafficPolicy: Local
```

---

## 3) Deploy demo apps + Ingress

```bash
kubectl apply -f k8s-demo/
kubectl -n demo rollout status deploy/httpbun1 --timeout=180s
kubectl -n demo rollout status deploy/httpbun2 --timeout=180s
```

---

## 4) Get the public address & test

```bash
LB=$(kubectl -n ingress-nginx get svc ingress-nginx-controller   -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{.status.loadBalancer.ingress[0].ip}')
echo "$LB"

curl -s "http://$LB/httpbun1/get" | jq -r .url
curl -s "http://$LB/httpbun2/get" | jq -r .url
# A 404 at "/" is expected; use the paths above.
```

---

## 5) Grafana & Prometheus (via port-forward)

Keep these internal; use local tunnels.

```bash
# Prometheus → http://127.0.0.1:9090
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090

# Grafana → http://127.0.0.1:3000
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80

# Grafana admin password
kubectl -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Import the dashboards from `observability/dashboards/` and select the **Prometheus** data source.

---

## 6) Generate traffic

```bash
for i in {1..300}; do
  curl -s "http://$LB/httpbun1/status/200" >/dev/null
  curl -s "http://$LB/httpbun2/status/200" >/dev/null
done
```

---

## Troubleshooting

- **ServiceMonitor error:** install kube-prometheus-stack first; then (re)install ingress with ServiceMonitor enabled.  
- **Controller CrashLoop + “unknown flag”**: on v1.12+ keep only `extraArgs.enable-metrics="true"`; remove deprecated flags.  
- **No public access:** ensure LB security group allows TCP 80/443 from 0.0.0.0/0 and public subnets are tagged `kubernetes.io/role/elb=1`.

---
