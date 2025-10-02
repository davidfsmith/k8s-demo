# HTTPBin + NGINX Ingress (Helm) Demo

A minimal demo that deploys two HTTPBin apps behind the **Helm-installed NGINX Ingress Controller** on Minikube.
Manual steps come first; a Makefile is provided at the end for shortcuts.

## Prerequisites

- [minikube](https://minikube.sigs.k8s.io/docs/) (Docker driver recommended)
- [helm](https://helm.sh)
- [kubectl](https://kubernetes.io/docs/reference/kubectl/kubectl/)
- [jq](https://jqlang.org) (optional, used in a few examples)

Project structure (relevant bits):

```
k8s-demo/
  00-namespace.yaml
  10-httpbin1-deploy.yaml
  11-httpbin1-svc.yaml
  20-httpbin2-deploy.yaml
  21-httpbin2-svc.yaml
  30-ingress.yaml
observability/
  dashboards/               # JSON dashboards to import into Grafana
  README.md
```

## 1) Start a clean cluster

We use the Helm-based ingress controller (not the Minikube addon).

```bash
minikube start --driver=docker
```

If you previously enabled the addon:
```bash
minikube addons disable ingress || true
```

## 2) Install ingress-nginx via Helm (LoadBalancer, metrics exposed)

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx   -n ingress-nginx --create-namespace   --set controller.ingressClass=nginx   --set controller.metrics.enabled=true   --set controller.service.type=LoadBalancer

kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=300s
```

We purposely **do not** enable the ServiceMonitor yet. We’ll add observability later.

## 3) Deploy the demo apps + Ingress

```bash
kubectl apply -f .
kubectl -n demo rollout status deploy/httpbin1 --timeout=180s
kubectl -n demo rollout status deploy/httpbin2 --timeout=180s
```

Ensure your Ingress uses the Helm controller’s class:

```bash
kubectl -n demo get ingress demo-httpbin -o jsonpath='{.spec.ingressClassName}{"\n"}'
# If empty/different, set it:
kubectl -n demo patch ingress demo-httpbin --type=merge -p '{"spec":{"ingressClassName":"nginx"}}'
```

## 4) Test routing

### Option A — Port-forward (fast path)

```bash
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80
# New terminal:
curl -s http://127.0.0.1:8080/httpbin1/get | jq -r .url
curl -s http://127.0.0.1:8080/httpbin2/get | jq -r .url
```

#### Gnerate traffic

```bash
for i in {1..100}; do
  curl -s "http://127.0.0.1:8080/httpbin1/status/200" >/dev/null
  curl -s "http://127.0.0.1:8080/httpbin2/status/200" >/dev/null
done
```

### Option B — LoadBalancer (recommended)

```bash
# Terminal A
sudo -E minikube tunnel

# Terminal B
LBIP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "$LBIP"
curl -s "http://$LBIP/httpbin1/get" | jq -r .url
curl -s "http://$LBIP/httpbin2/get" | jq -r .url
```

404 at `/` is expected. Use `/httpbin1/*` and `/httpbin2/*` paths.

#### Gnerate traffic


```bash
for i in {1..100}; do
  curl -s "http://$LBIP/httpbin1/status/200" >/dev/null
  curl -s "http://$LBIP/httpbin2/status/200" >/dev/null
done
```


## 5) Add observability (Prometheus + Grafana)

Head to `observability/README.md` for clean, step-by-step instructions:
- Install `kube-prometheus-stack`
- Enable the ingress ServiceMonitor (Helm upgrade)
- Port-forward Grafana & Prometheus
- Import dashboards from `observability/dashboards/`

## Using the Makefile (shortcuts)

The Makefile mirrors the manual steps above.

```bash
# 0) Start cluster (no addon path)
make init

# 1) Install Helm ingress controller (LB + metrics)
make ingress

# 2) Deploy demo apps + ingress
make apply
make wait

# 3a) Port-forward and test
make pf
make test-pf

# 3b) Or use LoadBalancer + tunnel
sudo -E minikube tunnel &
make url
make test-lb

# 4) Clean up demo
make clean
```

See target list: `make help`.

## Troubleshooting

- Ensure `spec.ingressClassName: nginx` on the demo Ingress.
- If LB curls time out, confirm tunnel is running and the Service has an external IP.
- For metrics on the controller: `kubectl -n ingress-nginx exec -it <pod> -- wget -qO- http://127.0.0.1:10254/metrics | head`
