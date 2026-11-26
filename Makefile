.DEFAULT_GOAL := help
SHELL := /bin/bash

.PHONY: help up preflight plan apply infra status verify slides fmt validate graph output down clean

help: ## Show the available targets
	@echo "Terraform + Confluent Cloud brownbag"
	@echo
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "  Start here:  make up      (~25 min)"
	@echo "  kubectl:     export KUBECONFIG=\$$PWD/.kubeconfig"

up: preflight infra status ## Everything: preflight -> Terraform

# --- Terraform ---------------------------------------------------------------

preflight: ## Check AWS quotas, SCPs and credentials before spending 20 min on an apply
	./scripts/preflight.sh

plan: ## terraform plan, saved to terraform/tfplan
	./scripts/plan.sh

apply: ## Apply the saved plan (or run a full apply if there is none)
	./scripts/infra.sh

infra: ## Terraform: VPCs, TGW, EKS, PrivateLink, Confluent Cloud env + Enterprise cluster
	./scripts/infra.sh

fmt: ## terraform fmt -recursive
	terraform -chdir=terraform fmt -recursive

validate: ## terraform validate (no cloud credentials needed)
	@terraform -chdir=terraform init -backend=false -input=false >/dev/null && \
	 terraform -chdir=terraform validate

graph: ## Render the dependency graph to graph.svg (needs graphviz)
	@command -v dot >/dev/null || { echo "graphviz is not installed: brew install graphviz" >&2; exit 1; }
	@terraform -chdir=terraform graph | dot -Tsvg >graph.svg && echo "wrote graph.svg"

output: ## Show all Terraform outputs
	@terraform -chdir=terraform output

# --- Demo --------------------------------------------------------------------

status: ## Terraform outputs and EKS nodes
	./scripts/status.sh

verify: ## Prove the private path to Confluent Cloud from a pod in the VPC
	./scripts/verify.sh

slides: ## The brownbag deck (Slidev) on http://localhost:3030 - needs Node 20+
	cd slides && { [ -d node_modules ] || npm install; } && npx slidev --port 3030 --open

# --- Teardown ----------------------------------------------------------------

down: ## Delete everything, in the right order
	./scripts/down.sh

clean: ## Remove local scratch files (keeps Terraform state)
	rm -f .kubeconfig graph.svg terraform/tfplan
