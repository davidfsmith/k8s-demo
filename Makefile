# ---- Demo Makefile (Helm ingress ready) ----
.PHONY: help init init-no-addon ingress-helm-install ingress-helm-wait ingress-helm-uninstall \
        apply wait port-forward pf-helm pf-stop lb tunnel url add-host tls test-pf test-lb \
        verify cleanup nuke demo-pf demo-lb

# ----- Config -----
NAMESPACE        ?= demo
INGRESS_NS       ?= ingress-nginx
HELM_RELEASE     ?= ingress-nginx
HELM_CHART       ?= ingress-nginx/ingress-nginx
INGRESS_SVC      ?= ingress-nginx-controller
HOST             ?= demo.127.0.0.1.nip.io
ING_NAME         ?= demo-httpbin

K8S_DIR          ?= k8s-demo
HTTPBIN1_DEPLOY  ?= $(K8S_DIR)/10-httpbin1-deploy.yaml
HTTPBIN1_SVC     ?= $(K8S_DIR)/11-httpbin1-svc.yaml
HTTPBIN2_DEPLOY  ?= $(K8S_DIR)/20-httpbin2-deploy.yaml
HTTPBIN2_SVC     ?= $(K8S_DIR)/21-httpbin2-svc.yaml
INGRESS_FILE     ?= $(K8S_DIR)/30-ingress.yaml
NS_FILE          ?= $(K8S_DIR)/00-namespace.yaml

help:
	@echo "Demo Makefile (Helm-based ingress capable)"
	@echo "Cluster:"
	@echo "  init              - Start minikube & enable addon ingress (legacy path)"
	@echo "  init-no-addon     - Start minikube without addon (use Helm controller)"
	@echo "Ingress (Helm):"
	@echo "  ingress-helm-install   - Install ingress-nginx via Helm (LB + metrics + ServiceMonitor)"
	@echo "  ingress-helm-wait      - Wait for controller to be ready"
	@echo "  ingress-helm-uninstall - Uninstall Helm ingress and delete namespace"
	@echo "Demo:"
	@echo "  apply            - Apply httpbin apps + ingress"
	@echo "  wait             - Wait for demo pods to be ready"
	@echo "Access:"
	@echo "  pf-helm          - Port-forward Helm controller svc → http://127.0.0.1:8080 (FG)"
	@echo "  port-forward     - Port-forward controller svc (alias of pf-helm)"
	@echo "  lb               - Ensure controller svc is LoadBalancer"
	@echo "  tunnel           - Print minikube tunnel hint"
	@echo "  url              - Show LB IP and test URLs"
	@echo "TLS/host:"
	@echo "  add-host         - Patch Ingress host to $(HOST)"
	@echo "  tls              - Create mkcert TLS secret and patch Ingress (requires mkcert)"
	@echo "Tests:"
	@echo "  test-pf          - Curl endpoints via 127.0.0.1:8080"
	@echo "  test-lb          - Curl endpoints via LB IP"
	@echo "Maintenance:"
	@echo "  verify           - Show key resources"
	@echo "  cleanup          - Delete demo k8s resources"
	@echo "  nuke             - Reset controller svc to NodePort (cleanup ingress Helm optional)"
	@echo ""
	@echo "Happy path (Helm): make init-no-addon ingress-helm-install ingress-helm-wait apply wait pf-helm test-pf"

# ----- Cluster bring-up -----
init:
	minikube start --driver=docker
	minikube addons enable ingress
	kubectl -n $(INGRESS_NS) wait --for=condition=available deploy/$(INGRESS_SVC) --timeout=240s

init-no-addon:
	minikube start --driver=docker
	@echo "Ingress addon not enabled. Next: 'make ingress-helm-install'."

# ----- Helm-based ingress controller -----
ingress-helm-install:
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
	helm repo update
	helm upgrade --install $(HELM_RELEASE) $(HELM_CHART) -n $(INGRESS_NS) --create-namespace \
	  --set controller.ingressClass=nginx \
	  --set controller.metrics.enabled=true \
	  --set controller.metrics.serviceMonitor.enabled=true \
	  --set controller.metrics.serviceMonitor.namespace=monitoring \
	  --set controller.metrics.serviceMonitor.additionalLabels.release=monitoring \
	  --set controller.service.type=LoadBalancer
	@echo "Helm ingress installed. Consider: 'sudo -E minikube tunnel' for LoadBalancer IP."

ingress-helm-wait:
	kubectl -n $(INGRESS_NS) rollout status deploy/$(INGRESS_SVC) --timeout=300s

ingress-helm-uninstall:
	-helm uninstall $(HELM_RELEASE) -n $(INGRESS_NS) || true
	-kubectl delete ns $(INGRESS_NS) --wait=false || true

# ----- Demo app -----
apply:
	kubectl apply -f $(NS_FILE)
	kubectl apply -f $(HTTPBIN1_DEPLOY) -f $(HTTPBIN1_SVC)
	kubectl apply -f $(HTTPBIN2_DEPLOY) -f $(HTTPBIN2_SVC)
	kubectl apply -f $(INGRESS_FILE)

wait:
	kubectl -n $(NAMESPACE) rollout status deploy/httpbin1 --timeout=180s
	kubectl -n $(NAMESPACE) rollout status deploy/httpbin2 --timeout=180s

# ----- Access paths -----
pf-helm:
	@echo "Forwarding http://127.0.0.1:8080 → $(INGRESS_NS)/svc/$(INGRESS_SVC):80 (Ctrl+C to stop)"
	kubectl -n $(INGRESS_NS) port-forward svc/$(INGRESS_SVC) 8080:80

port-forward: pf-helm

lb:
	kubectl -n $(INGRESS_NS) patch svc $(INGRESS_SVC) -p '{"spec":{"type":"LoadBalancer"}}' --type=merge

tunnel:
	@echo "Run this in another terminal with sudo:"
	@echo "  sudo -E minikube tunnel"

url:
	@echo "LB IP (if tunnel running):"
	@LBIP=$$(kubectl -n $(INGRESS_NS) get svc $(INGRESS_SVC) -o jsonpath='{.status.loadBalancer.ingress[0].ip}'); \
	echo $$LBIP; \
	echo "Try:"; \
	echo "  http://$$LBIP/httpbin1/get"; \
	echo "  http://$$LBIP/httpbin2/get"

# ----- Host & TLS -----
add-host:
	kubectl -n $(NAMESPACE) patch ingress $(ING_NAME) --type='json' \
	  -p='[{"op":"add","path":"/spec/rules/0/host","value":"$(HOST)"}]'
	@echo "Host set to $(HOST)."

tls:
	@which mkcert >/dev/null || (echo "mkcert not found. Install mkcert or skip TLS."; exit 1)
	mkcert -install
	mkcert $(HOST)
	kubectl -n $(NAMESPACE) delete secret demo-tls --ignore-not-found
	kubectl -n $(NAMESPACE) create secret tls demo-tls --cert=$(HOST).pem --key=$(HOST)-key.pem
	kubectl -n $(NAMESPACE) patch ingress $(ING_NAME) --type='json' \
	  -p='[{"op":"add","path":"/spec/tls","value":[{"hosts":["$(HOST)"],"secretName":"demo-tls"}]}]'
	@echo "TLS enabled for https://$(HOST)/"

# ----- Tests -----
test-pf:
	@echo "Testing via 127.0.0.1:8080"
	@curl -s http://127.0.0.1:8080/httpbin1/get | jq -r '.url' || true
	@curl -s http://127.0.0.1:8080/httpbin2/get | jq -r '.url' || true

test-lb:
	@LBIP=$$(kubectl -n $(INGRESS_NS) get svc $(INGRESS_SVC) -o jsonpath='{.status.loadBalancer.ingress[0].ip}'); \
	echo "LBIP=$$LBIP"; \
	curl -s "http://$$LBIP/httpbin1/get" | jq -r '.url' || true; \
	curl -s "http://$$LBIP/httpbin2/get" | jq -r '.url' || true

# ----- Info / cleanup -----
verify:
	@echo "--- Ingress Controller (svc) ---"
	kubectl -n $(INGRESS_NS) get svc $(INGRESS_SVC) -o wide
	@echo "--- Pods (controller) ---"
	kubectl -n $(INGRESS_NS) get pods -l app.kubernetes.io/component=controller -o wide
	@echo "--- Demo ---"
	kubectl -n $(NAMESPACE) get pods,svc,ingress

cleanup:
	-kubectl delete -f $(INGRESS_FILE) || true
	-kubectl delete -f $(HTTPBIN2_SVC) || true
	-kubectl delete -f $(HTTPBIN2_DEPLOY) || true
	-kubectl delete -f $(HTTPBIN1_SVC) || true
	-kubectl delete -f $(HTTPBIN1_DEPLOY) || true
	-kubectl delete -f $(NS_FILE) || true

nuke: cleanup
	-kubectl -n $(INGRESS_NS) patch svc $(INGRESS_SVC) -p '{"spec":{"type":"NodePort"}}' --type=merge || true
	@echo "Demo cleaned. Controller svc set back to NodePort."
