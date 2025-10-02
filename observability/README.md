# Observability for the Demo (Prometheus + Grafana)

This adds kube-prometheus-stack, enables scraping of the ingress controller, and imports dashboards.

## Prerequisites

- Baseline demo is running (Ingress via Helm, apps responding)
- [helm](https://helm.sh)
- [kubectl](https://kubernetes.io/docs/reference/kubectl/kubectl/)
- [jq](https://jqlang.org) (optional)

Dashboards live in `observability/dashboards/`.

## 1) Install kube-prometheus-stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace

# Wait for Grafana
kubectl -n monitoring rollout status deploy/monitoring-grafana --timeout=300s
```

## 2) Enable the ingress ServiceMonitor

Reconfigure the Helm ingress controller to create a ServiceMonitor in `monitoring`.

```bash
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.metrics.enabled=true \
  --set controller.metrics.serviceMonitor.enabled=true \
  --set controller.metrics.serviceMonitor.namespace=monitoring \
  --set controller.metrics.serviceMonitor.additionalLabels.release=monitoring \
  --set controller.extraArgs.enable-metrics=true \
  --set controller.extraArgs.enable-metrics-labels=true \
  --set controller.extraArgs.metrics-per-ingress=true \
  --set controller.extraArgs.metrics-per-service=true \
  --set controller.extraArgs.metrics-per-location=true \
  --set controller.service.type=LoadBalancer
```

**Note:** This can generate a lot of data and shouldn't be used for production

## 3) Port-forward Grafana and Prometheus

```bash
# Grafana → http://127.0.0.1:3000 (user: admin, password below)
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80

# Prometheus → http://127.0.0.1:9090
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
```

Get Grafana admin password:

```bash
kubectl -n monitoring get secret monitoring-grafana   -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

## 4) Import dashboards

**UI path (recommended first time):**

- Open [http://127.0.0.1:3000]() → Dashboards → Import
- Upload each JSON from `observability/dashboards/`

**Queries used (robust across controller versions):**

```
sum by (ingress, path) (rate(nginx_ingress_controller_requests_total[1m])) or sum by (ingress, path) (rate(nginx_ingress_controller_requests[1m]))
```

```
sum by (ingress, path) (increase(nginx_ingress_controller_requests_total[5m])) or sum by (ingress, path) (increase(nginx_ingress_controller_requests[5m]))
```

```
histogram_quantile(0.95, sum by (le) rate(nginx_ingress_controller_request_duration_seconds_bucket[5m])))
```
(The last one requires the duration histogram to be present.)

## Using the Makefile (shortcuts)

From the `observability/` directory:

```bash
# 1) Install monitoring stack
make obs-install

# 2) Enable ingress ServiceMonitor (runs a helm upgrade as above)
make obs-nginx-sm

# 3) Port-forward Grafana/Prometheus (run in separate terminals)
make pf-grafana
make pf-prom

# 4) Print Grafana admin password
make grafana-pass
```
