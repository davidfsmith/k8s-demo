# Version-aware values for ingress-nginx

Pick the file that matches your controller version:

| Controller version | File                         | Notes                                |
|--------------------|------------------------------|--------------------------------------|
| v1.12 and newer    | values.v1.12plus.yaml        | Only `enable-metrics` is valid       |
| v1.10 – v1.11      | values.v1.10-1.11.yaml       | Supports `enable-metrics-labels` and `metrics-per-*` flags |

## Usage

Set the controller image tag explicitly and pass the matching values file.

### v1.12+
```bash
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx   -n ingress-nginx --create-namespace   --set controller.image.tag=v1.13.3   -f values.v1.12plus.yaml
```

### v1.10–v1.11
```bash
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx   -n ingress-nginx --create-namespace   --set controller.image.tag=v1.11.3   -f values.v1.10-1.11.yaml
```

> Tip: On Minikube, either run `minikube tunnel` (to use LoadBalancer) or change `controller.service.type` to `NodePort` in the file.
