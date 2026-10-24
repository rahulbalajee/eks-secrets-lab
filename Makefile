SCHEMAS := -schema-location default -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

.PHONY: check go terraform manifests lab-up lab-down

check: go terraform manifests

go:
	cd app && go vet ./... && go test ./...

terraform:
	terraform -chdir=terraform fmt -check -recursive
	terraform -chdir=terraform init -backend=false -input=false >/dev/null
	terraform -chdir=terraform validate
	terraform -chdir=terraform/examples/irsa init -backend=false -input=false >/dev/null
	terraform -chdir=terraform/examples/irsa validate

manifests:
	kubectl kustomize k8s/overlays/eks | kubeconform -strict -summary $(SCHEMAS) -
	kubectl kustomize k8s/overlays/lab | kubeconform -strict -summary $(SCHEMAS) -

lab-up:
	./lab/up.sh

lab-down:
	./lab/down.sh
