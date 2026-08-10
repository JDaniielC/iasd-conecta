.PHONY: deploy-web

# Publica o Flutter Web em Cloud Storage + Cloud CDN. MANUAL enquanto
# iam.disableServiceAccountKeyCreation bloquear o CI (ver
# .tickets/IASD-CI-GCS-UPLOAD.md e specs/020-deploy-gcs-cdn/).
#
# Pré-requisitos, uma vez por máquina/pessoa:
#   1. gcloud auth login   — com a conta que tem roles/storage.objectAdmin no bucket
#                             e roles/compute.loadBalancerAdmin no projeto
#   2. .env na raiz do repo, com as DUAS chaves públicas de produção
#      (SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY) — nunca SERVICE_ROLE_KEY nem ADMIN_*,
#      porque .env é assets: no pubspec.yaml e vai DENTRO do bundle público.
BUCKET := gs://conecta-iasd-site
URL_MAP := conecta-iasd-site-url-map
ASSET_CACHE_CONTROL := public, max-age=3600
HTML_CACHE_CONTROL := no-cache, max-age=0, must-revalidate

deploy-web:
	@test -f .env || { echo "erro: .env ausente. Ver Makefile — precisa das 2 chaves públicas de produção."; exit 1; }
	@gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q . || { echo "erro: nenhuma conta gcloud ativa. Rode: gcloud auth login"; exit 1; }
	flutter pub get
	flutter build web --release
	@keys=$$(grep -oE '^[A-Z_]+=' build/web/assets/.env | tr -d '=' | sort | tr '\n' ' '); \
	expected="SUPABASE_PUBLISHABLE_KEY SUPABASE_URL "; \
	if [ "$$keys" != "$$expected" ]; then \
		echo "erro: build/web/assets/.env tem chaves além das duas públicas. Encontrado: $$keys"; \
		exit 1; \
	fi
	# Passada aditiva: sobe tudo, não apaga nada — o site antigo continua servindo até aqui.
	gcloud storage rsync --recursive \
		--exclude='^\.last_build_id$$' \
		--cache-control="$(ASSET_CACHE_CONTROL)" \
		build/web $(BUCKET)
	# Passada destrutiva: só agora remove o que o build novo não tem mais.
	gcloud storage rsync --recursive \
		--delete-unmatched-destination-objects \
		--exclude='^\.last_build_id$$' \
		--cache-control="$(ASSET_CACHE_CONTROL)" \
		build/web $(BUCKET)
	gcloud storage objects update $(BUCKET)/index.html \
		--cache-control="$(HTML_CACHE_CONTROL)"
	gcloud compute url-maps invalidate-cdn-cache $(URL_MAP) --path "/*"
	@echo "Publicado. Site: http://35.211.105.176"
