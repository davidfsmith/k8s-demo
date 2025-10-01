.PHONY: help init apply wait port-forward pf-stop lb tunnel url add-host tls test-pf test-lb verify cleanup nuke demo-pf demo-lb

# ==== Config (root) ====
NAMESPACE ?= demo
INGRESS_NS ?= ingress-nginx
INGRESS_SVC ?= ingress-nginx-controller
HOST ?= demo.127.0.0.1.nip.io

help:
	@echo ""
	@echo "Root Makefile — httpbin demo & ingress networking"
	@echo "Targets:"
	@echo "  init         - Start minikube & enable ingress"
	@echo "  apply        - Apply demo manifests in ./k8s-demo"
	@echo "  wait         - Wait for httpbin deployments to be ready"
	@echo "  port-forward - Port-forward ingress controller to localhost:8080 (FG)"
	@echo "  pf-stop      - Stop any listener on localhost:8080"
	@echo "  lb           - Patch controller Service to LoadBalancer"
	@echo "  tunnel       - Print minikube tunnel command (run separately)"
	@echo "  url          - Show LB IP and service details"
	@echo "  add-host     - Add nip.io hostname to Ingress spec.rules[0].host"
	@echo "  tls          - Create mkcert TLS & enable HTTPS on Ingress"
	@echo "  test-pf      - Test endpoints via port-forward (http://127.0.0.1:8080)"
	@echo "  test-lb      - Test endpoints via LB IP (requires tunnel or MetalLB)"
	@echo "  verify       - Show controller, ingress, endpoints"
	@echo "  cleanup      - Remove demo resources"
	@echo "  nuke         - cleanup + revert controller svc to NodePort"
	@echo "  demo-pf      - init+apply+wait then foreground port-forward"
	@echo "  demo-lb      - init+apply+wait then switch to LoadBalancer"
	@echo ""

init:
	minikube start --driver=docker
	minikube addons enable ingress
	kubectl -n $(INGRESS_NS) wait --for=condition=available deploy/$(INGRESS_SVC) --timeout=180s

apply:
	kubectl apply -f 00-namespace.yaml
	kubectl apply -f 10-httpbin1-deploy.yaml -f 11-httpbin1-svc.yaml
	kubectl apply -f 20-httpbin2-deploy.yaml -f 21-httpbin2-svc.yaml
	kubectl apply -f 30-ingress.yaml

wait:
	kubectl -n $(NAMESPACE) rollout status deploy/httpbin1 --timeout=120s
	kubectl -n $(NAMESPACE) rollout status deploy/httpbin2 --timeout=120s

port-forward:
	@echo "Forwarding http://127.0.0.1:8080 → $(INGRESS_NS)/svc/$(INGRESS_SVC):80 (Ctrl+C to stop)"
	kubectl -n $(INGRESS_NS) port-forward svc/$(INGRESS_SVC) 8080:80

pf-stop:
	-@lsof -i :8080 -sTCP:LISTEN -t | xargs -r kill

lb:
	kubectl -n $(INGRESS_NS) patch svc $(INGRESS_SVC) -p '{"spec":{"type":"LoadBalancer"}}'

tunnel:
	@echo "Run this in a separate terminal (may need sudo):"
	@echo "  sudo -E minikube tunnel"

url:
	@kubectl -n $(INGRESS_NS) get svc $(INGRESS_SVC) -o wide
	@echo "LBIP=$$(kubectl -n $(INGRESS_NS) get svc $(INGRESS_SVC) -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
	@echo "If LBIP is empty, wait for External IP (or ensure tunnel is running)."

add-host:
	kubectl -n $(NAMESPACE) patch ingress demo-httpbin --type='json' \
	  -p='[{"op":"add","path":"/spec/rules/0/host","value":"$(HOST)"}]'
	@echo "Patched Ingress host to $(HOST)"
	@echo "Example curl:"
	@echo "  LBIP=$$(kubectl -n $(INGRESS_NS) get svc $(INGRESS_SVC) -o jsonpath='{.status.loadBalancer.ingress[0].ip}') && \\"
	@echo "  curl -s --noproxy '*' -H \"Host: $(HOST)\" \"http://$$LBIP/httpbin1/get\" | jq -r '.url'"

tls:
	@echo "Generating local TLS with mkcert for $(HOST) ..."
	@which mkcert >/dev/null || (echo "mkcert not found. Install mkcert first." && exit 1)
	mkcert -install
	mkcert $(HOST)
	kubectl -n $(NAMESPACE) create secret tls demo-tls \
	  --cert=$(HOST).pem \
	  --key=$(HOST)-key.pem --dry-run=client -o yaml | kubectl apply -f -
	kubectl -n $(NAMESPACE) patch ingress demo-httpbin --type='json' -p='[ \
	  {"op":"add","path":"/spec/tls","value":[{"hosts":["$(HOST)"],"secretName":"demo-tls"}]}, \
	  {"op":"add","path":"/metadata/annotations/nginx.ingress.kubernetes.io~1force-ssl-redirect","value":"true"} \
	]'
	@echo "Browse: https://$(HOST)/httpbin1/get"

test-pf:
	@for p in httpbin1 httpbin2; do \
	  echo "Testing http://127.0.0.1:8080/$$p/get"; \
	  curl -s "http://127.0.0.1:8080/$$p/get" | jq -r '.url' || true; \
	done

test-lb:
	@LBIP=$$(kubectl -n $(INGRESS_NS) get svc $(INGRESS_SVC) -o jsonpath='{.status.loadBalancer.ingress[0].ip}'); \
	if [ -z "$$LBIP" ]; then echo "No LB IP yet. Run 'make url' and ensure 'minikube tunnel' is active."; exit 1; fi; \
	for p in httpbin1 httpbin2; do \
	  echo "Testing http://$$LBIP/$$p/get"; \
	  curl -s --noproxy '*' "http://$$LBIP/$$p/get" | jq -r '.url' || true; \
	done

verify:
	kubectl -n $(NAMESPACE) get deploy,svc,ingress
	kubectl -n $(INGRESS_NS) get pods,svc
	kubectl -n $(NAMESPACE) get ep httpbin1 httpbin2
	kubectl -n $(NAMESPACE) describe ingress demo-httpbin | sed -n '1,200p'

cleanup:
	-kubectl delete -f 30-ingress.yaml
	-kubectl delete -f 21-httpbin2-svc.yaml -f 20-httpbin2-deploy.yaml
	-kubectl delete -f 11-httpbin1-svc.yaml -f 10-httpbin1-deploy.yaml
	-kubectl delete -f 00-namespace.yaml

nuke: cleanup
	-kubectl -n $(INGRESS_NS) patch svc $(INGRESS_SVC) -p '{"spec":{"type":"NodePort"}}'

demo-pf: init apply wait port-forward

demo-lb: init apply wait lb
	@echo "Now run 'sudo -E minikube tunnel' in another terminal, then 'make url test-lb'."
