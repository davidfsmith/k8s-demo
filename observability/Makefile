# Observability Makefile — kube-prometheus-stack + helpers
.PHONY: help obs-install obs-nginx-sm pf-grafana pf-prom grafana-pass obs-clean

OBS_NS        ?= monitoring
INGRESS_NS    ?= ingress-nginx
HELM_MON      ?= monitoring
HELM_ING      ?= ingress-nginx

help:
	@echo "Targets:"
	@echo "  obs-install  - Install kube-prometheus-stack (Prometheus, Grafana, CRDs)"
	@echo "  obs-nginx-sm - Enable ingress-nginx ServiceMonitor via helm upgrade"
	@echo "  pf-grafana   - Port-forward Grafana to http://127.0.0.1:3000 (FG)"
	@echo "  pf-prom      - Port-forward Prometheus to http://127.0.0.1:9090 (FG)"
	@echo "  grafana-pass - Print Grafana admin password"
	@echo "  obs-clean    - Uninstall monitoring stack (danger)"

obs-install:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install $(HELM_MON) prometheus-community/kube-prometheus-stack \
	  -n $(OBS_NS) --create-namespace
	kubectl -n $(OBS_NS) rollout status deploy/$(HELM_MON)-grafana --timeout=300s

obs-nginx-sm:
	helm upgrade --install $(HELM_ING) ingress-nginx/ingress-nginx -n $(INGRESS_NS) \
	  --set controller.metrics.enabled=true \
	  --set controller.metrics.serviceMonitor.enabled=true \
	  --set controller.metrics.serviceMonitor.namespace=$(OBS_NS) \
	  --set controller.metrics.serviceMonitor.additionalLabels.release=$(HELM_MON)

pf-grafana:
	kubectl -n $(OBS_NS) port-forward svc/$(HELM_MON)-grafana 3000:80

pf-prom:
	kubectl -n $(OBS_NS) port-forward svc/$(HELM_MON)-kube-prometheus-prometheus 9090:9090

grafana-pass:
	@kubectl -n $(OBS_NS) get secret $(HELM_MON)-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo

obs-clean:
	-helm uninstall $(HELM_MON) -n $(OBS_NS) || true
	-kubectl delete ns $(OBS_NS) --wait=false || true
