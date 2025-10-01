# Kubernetes Demo – Minikube + Ingress + 2x httpbin Apps

Spin up a tiny demo on Minikube with an NGINX Ingress routing to **two httpbin services** on separate paths.

```
Ingress (nginx)
 ├── /httpbin1 → Service httpbin1 → Deployment httpbin1 (kennethreitz/httpbin)
 └── /httpbin2 → Service httpbin2 → Deployment httpbin2 (kennethreitz/httpbin)

                   ┌─────────────────────────┐
                   │   Minikube Node         │
                   │   (127.0.0.1 via tunnel)│
                   └─────────────┬───────────┘
                                 │
                         Ingress Controller
                         (nginx-ingress)
                                 │
          ┌──────────────────────┴───────────────────────┐
          │                                              │
   /httpbin1 → Service httpbin1                  /httpbin2 → Service httpbin2
               (ClusterIP)                                  (ClusterIP)
          │                                              │
   ┌──────┴─────────┐                            ┌───────┴─────────┐
   │ Deployment     │                            │ Deployment      │
   │ httpbin1       │                            │ httpbin2        │
   │ (kennethreitz/ │                            │ (kennethreitz/  │
   │  httpbin pod)  │                            │  httpbin pod)   │
   └────────────────┘                            └─────────────────┘
```

## Prerequisites
- [minikube](https://minikube.sigs.k8s.io/docs/) (Docker driver recommended)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [jq](https://jqlang.org) (for pretty test output)
- [mkcert](https://github.com/FiloSottile/mkcert) (Optional) if you want local TLS

## TL;DR (fast path)

```bash
# 0) Start / enable ingress
minikube start --driver=docker
minikube addons enable ingress
kubectl -n ingress-nginx wait --for=condition=available deploy/ingress-nginx-controller --timeout=180s
```

## Deploy

```bash
kubectl apply -f 00-namespace.yaml
kubectl apply -f 10-httpbin1-deploy.yaml -f 11-httpbin1-svc.yaml
kubectl apply -f 20-httpbin2-deploy.yaml -f 21-httpbin2-svc.yaml
kubectl apply -f 30-ingress.yaml

# Wait for pods
kubectl -n demo rollout status deploy/httpbin1 --timeout=120s
kubectl -n demo rollout status deploy/httpbin2 --timeout=120s
```

## Access – Option A (recommended for demos): Port-forward the controller

```
Browser / curl
    │  http://127.0.0.1:8080/…
    ▼
Local port-forward
(kubectl -n ingress-nginx port-forward
 svc/ingress-nginx-controller 8080:80)
    │  TCP 127.0.0.1:8080 → :80 in cluster
    ▼
Ingress Controller (nginx)
    │  /httpbin1, /httpbin2 rules (regex + rewrite)
    ├──────────────► Service httpbin1 (ClusterIP) ─► Pod: httpbin1
    └──────────────► Service httpbin2 (ClusterIP) ─► Pod: httpbin2
```

No networking faff, always works locally.

```bash
# Terminal 1
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80
```

**Quick test (one-liner):**

```bash
for p in httpbin1 httpbin2; do 
  echo "Testing /$p ..."
  curl -s "http://127.0.0.1:8080/$p/get" | jq -r '.url'
done
```

Open in a browser:

- http://127.0.0.1:8080/httpbin1/get  
- http://127.0.0.1:8080/httpbin2/get

## Access – Option B (clean demo URL): LoadBalancer via `minikube tunnel`

```
Browser / curl
    │  http://127.0.0.1/…   (LB IP often becomes 127.0.0.1)
    ▼
minikube tunnel
(emulates cloud LB; binds host :80 → Service:80)
    │
    ▼
Service: ingress-nginx-controller (LoadBalancer)
    │  forwards to controller Pods
    ▼
Ingress Controller (nginx)
    │  /httpbin1, /httpbin2 rules (regex + rewrite)
    ├──────────────► Service httpbin1 (ClusterIP) ─► Pod: httpbin1
    └──────────────► Service httpbin2 (ClusterIP) ─► Pod: httpbin2
```

Change the controller Service to `LoadBalancer` and run the tunnel. On macOS this often binds to **127.0.0.1** (expected).

```bash
# Switch svc to LoadBalancer
kubectl -n ingress-nginx patch svc/ingress-nginx-controller -p '{"spec":{"type":"LoadBalancer"}}'

# Create the tunnel (leave this running; may need sudo)
sudo -E minikube tunnel
```

New terminal:

```bash
# Wait for External IP and test
kubectl -n ingress-nginx get svc ingress-nginx-controller --watch
```

Once you see an External IP, capture and test:

```bash
LBIP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "LB IP: $LBIP"

for p in httpbin1 httpbin2; do
  echo "Testing via LB http://$LBIP/$p/get ..."
  curl -s --noproxy '*' "http://$LBIP/$p/get" | jq -r '.url'
done
```

If `LBIP` is `127.0.0.1`, this is normal with the Docker driver + tunnel.

### Friendly hostname (no /etc/hosts)

```bash
HOST="demo.127.0.0.1.nip.io"
kubectl -n demo patch ingress demo-httpbin --type='json'   -p='[{"op":"add","path":"/spec/rules/0/host","value":"'"$HOST"'"}]'
```

When a host is set, send the Host header when curling:

```bash
for p in httpbin1 httpbin2; do
  echo "Testing via HOST http://$HOST/$p/get ..."
  curl -s --noproxy '*' -H "Host: $HOST" "http://$HOST/$p/get" | jq -r '.url'
done
```

Open in a browser:

- [http://demo.127.0.0.1.nip.io/httpbin1/get]()
- [http://demo.127.0.0.1.nip.io/httpbin2/get]()

### Optional: Local TLS for a polished demo

Use `mkcert` (recommended) to generate a local-trusted cert for the hostname and add TLS to the Ingress.

```bash
# Install local CA and issue a cert
mkcert -install
mkcert demo.127.0.0.1.nip.io

# Create TLS secret
kubectl -n demo create secret tls demo-tls   --cert=demo.127.0.0.1.nip.io.pem   --key=demo.127.0.0.1.nip.io-key.pem

# Patch Ingress to enable TLS and force HTTPS
kubectl -n demo patch ingress demo-httpbin --type='json' -p='[
  {"op":"add","path":"/spec/tls","value":[{"hosts":["demo.127.0.0.1.nip.io"],"secretName":"demo-tls"}]},
  {"op":"add","path":"/metadata/annotations/nginx.ingress.kubernetes.io~1force-ssl-redirect","value":"true"}
]'
```

Browse:

- [https://demo.127.0.0.1.nip.io/httpbin1/get]()
- [https://demo.127.0.0.1.nip.io/httpbin2/get]()

> If you prefer a non-localhost External IP, enable the **MetalLB** addon and configure a pool (e.g., `192.168.49.100-192.168.49.110`). This requires your host to route to the Minikube subnet (VPNs often block this).

```bash
minikube addons enable metallb
minikube addons configure metallb   # follow prompts to set an IP range
kubectl -n ingress-nginx patch svc ingress-nginx-controller   -p '{"spec":{"type":"LoadBalancer","externalTrafficPolicy":"Cluster"}}'
```

## Verify

```bash
kubectl -n demo get deploy,svc,ingress
kubectl -n ingress-nginx get pods,svc
kubectl -n demo describe ingress demo-httpbin | sed -n '1,200p'
```

## Troubleshooting

- **Ingress won’t create**: ensure the regex paths start with `/` and `pathType: ImplementationSpecific`, and `use-regex: "true"` is set.
- **Blank response on LB/127.0.0.1**: verify the controller is selected by your Ingress.
  - Check available classes: `kubectl get ingressclass -o wide`
  - The manifest uses `ingressClassName: nginx`. If your controller expects a different class (e.g. `ingress-nginx`), patch it:
```
kubectl -n demo patch ingress demo-httpbin -p '{"spec":{"ingressClassName":"ingress-nginx"}}'
```
- **404s from ingress**: endpoints might not be ready—re-try after pods are available, or run:
```
kubectl -n demo get ep httpbin1 httpbin2
```
- **NodePort doesn’t work**: often due to VPN route policies. Prefer **Option A** or **B**.
  - To test from inside the node: `minikube ssh -- "curl -I http://$(minikube ip):$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')/"`
- **Recreate the ingress cleanly**:
```
kubectl -n demo delete ingress demo-httpbin --ignore-not-found
kubectl apply -f 30-ingress.yaml
```

## Cleanup

```bash
kubectl delete \
  -f 30-ingress.yaml \
  -f 21-httpbin2-svc.yaml -f 20-httpbin2-deploy.yaml \
  -f 11-httpbin1-svc.yaml -f 10-httpbin1-deploy.yaml \
  -f 00-namespace.yaml
```


## Using the Makefile (root)

Prefer the step-by-step flow for learning, but when you want speed, the **Makefile** at repo root gives you handy shortcuts:

```bash
# Boot cluster, enable ingress, deploy demo, and wait for readiness
make init apply wait

# Quick local access via port-forward (http://127.0.0.1:8080)
make port-forward        # foreground; Ctrl+C to stop in this terminal
make test-pf             # curls both endpoints

# Clean 'cloud-like' access using a LoadBalancer + tunnel
make lb                  # switch ingress controller Service to LoadBalancer
sudo -E minikube tunnel  # run in another terminal; leave running
make url test-lb         # print the LB IP and test both endpoints

# Optional niceties
make add-host            # set host to demo.127.0.0.1.nip.io (uses nip.io)
make tls                 # create mkcert cert + enable HTTPS on the Ingress

# Inspect and tear down
make verify
make cleanup             # delete demo resources
make nuke                # also revert controller Service to NodePort
```