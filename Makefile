# Root Makefile — Helm ingress + demo
.PHONY: help init ingress apply wait pf test-pf url test-lb clean nuke verify

# Config
NAMESPACE      ?= demo
INGRESS_NS     ?= ingress-nginx
HELM_RELEASE   ?= ingress-nginx
HELM_CHART     ?= ingress-nginx/ingress-nginx
INGRESS_SVC    ?= ingress-nginx-controller

K8S_DIR        ?= "."
NS_FILE        ?= $(K8S_DIR)/00-namespace.yaml
ING_FILE       ?= $(K8S_DIR)/30-ingress.yaml

help:
	@echo "Targets:"
	@echo "  init     - Start minikube (no addon ingress enabled)"
	@echo "  ingress  - Install Helm ingress-nginx (LB + metrics)"
	@echo "  apply    - Apply demo manifests (namespace, apps, services, ingress)"
	@echo "  wait     - Wait for demo pods to be ready"
	@echo "  pf       - Port-forward controller svc → 127.0.0.1:8080 (FG)"
	@echo "  test-pf  - Test endpoints via port-forward"
	@echo "  url      - Show LoadBalancer IP and sample URLs"
	@echo "  test-lb  - Test endpoints via LoadBalancer IP"
	@echo "  verify   - Show key resources"
	@echo "  clean    - Delete demo resources"
	@echo "  nuke     - Remove ingress namespace (danger)"

init:
	minikube start --driver=docker

ingress:
	helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
	helm repo update
	helm upgrade --install $(HELM_RELEASE) $(HELM_CHART) -n $(INGRESS_NS) --create-namespace \
	  --set controller.ingressClass=nginx \
	  --set controller.metrics.enabled=true \
	  --set controller.service.type=LoadBalancer
	kubectl -n $(INGRESS_NS) rollout status deploy/$(INGRESS_SVC) --timeout=300s

apply:
	kubectl apply -f $(K8S_DIR)/

wait:
	kubectl -n $(NAMESPACE) rollout status deploy/httpbin1 --timeout=180s
	kubectl -n $(NAMESPACE) rollout status deploy/httpbin2 --timeout=180s

pf:
	@echo "Forwarding http://127.0.0.1:8080 → $(INGRESS_NS)/svc/$(INGRESS_SVC):80 (Ctrl+C to stop)"
	kubectl -n $(INGRESS_NS) port-forward svc/$(INGRESS_SVC) 8080:80

test-pf:
	@curl -s http://127.0.0.1:8080/httpbin1/get | jq -r .url || true
	@curl -s http://127.0.0.1:8080/httpbin2/get | jq -r .url || true

url:
	@LBIP=$$(kubectl -n $(INGRESS_NS) get svc $(INGRESS_SVC) -o jsonpath='{.status.loadBalancer.ingress[0].ip}'); \
	echo "LBIP=$$LBIP"; \
	echo "Try:"; \
	echo "  http://$$LBIP/httpbin1/get"; \
	echo "  http://$$LBIP/httpbin2/get"

test-lb:
	@LBIP=$$(kubectl -n $(INGRESS_NS) get svc $(INGRESS_SVC) -o jsonpath='{.status.loadBalancer.ingress[0].ip}'); \
	curl -s "http://$$LBIP/httpbin1/get" | jq -r .url || true; \
	curl -s "http://$$LBIP/httpbin2/get" | jq -r .url || true

verify:
	@echo "--- Ingress Controller ---"
	kubectl -n $(INGRESS_NS) get svc $(INGRESS_SVC) -o wide
	@echo "--- Demo ---"
	kubectl -n $(NAMESPACE) get pods,svc,ingress

clean:
	-kubectl delete -f $(ING_FILE) || true
	-kubectl -n $(NAMESPACE) delete svc httpbin1 httpbin2 --ignore-not-found
	-kubectl -n $(NAMESPACE) delete deploy httpbin1 httpbin2 --ignore-not-found
	-kubectl delete -f $(NS_FILE) || true

nuke:
	-helm uninstall $(HELM_RELEASE) -n $(INGRESS_NS) || true
	-kubectl delete ns $(INGRESS_NS) --wait=false || true
