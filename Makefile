.PHONY: deploy-web

# Publica o Flutter Web em Cloud Storage + Cloud CDN. MANUAL enquanto
# iam.disableServiceAccountKeyCreation bloquear o CI (ver
# .tickets/IASD-CI-GCS-UPLOAD.md e specs/020-deploy-gcs-cdn/).
#
# ---------------------------------------------------------------------
# 🔴 AS CHAVES ENTRAM POR --dart-define, E NUNCA POR ARQUIVO
# ---------------------------------------------------------------------
# A versão anterior deste alvo exigia um `.env` na raiz e conferia o que tinha
# ido parar em `build/web/assets/.env`. Isso partia de `.env` ser `assets:` no
# pubspec — e era exatamente esse o caminho do vazamento: um `flutter build web`
# LOCAL, rodado por quem tinha um `.env` completo no diretório, publicava o
# arquivo inteiro no bucket público.
#
# Hoje `.env` não é asset. A garantia deixou de ser "conferir o que vazou" e
# passou a ser "não existir arquivo capaz de vazar". Este alvo confere as duas
# coisas: que as chaves foram passadas, e que nenhum `.env` sobreviveu no bundle.
#
# Pré-requisitos, uma vez por máquina/pessoa:
#   1. gcloud auth login   — com a conta que tem roles/storage.objectAdmin no bucket
#                             e roles/compute.loadBalancerAdmin no projeto
#   2. as DUAS chaves públicas de produção no ambiente:
#        export SUPABASE_URL=https://<project-ref>.supabase.co
#        export SUPABASE_PUBLISHABLE_KEY=<chave publicável de produção>
#      NUNCA exporte SUPABASE_SERVICE_ROLE_KEY nem ADMIN_* aqui: o que entra em
#      --dart-define entra no JavaScript publicado, legível por qualquer pessoa.
BUCKET := gs://conecta-iasd-site
URL_MAP := conecta-iasd-site-url-map
ASSET_CACHE_CONTROL := public, max-age=3600
HTML_CACHE_CONTROL := no-cache, max-age=0, must-revalidate

deploy-web:
	@test -n "$$SUPABASE_URL" || { echo "erro: SUPABASE_URL não está no ambiente. Ver o cabeçalho deste Makefile."; exit 1; }
	@test -n "$$SUPABASE_PUBLISHABLE_KEY" || { echo "erro: SUPABASE_PUBLISHABLE_KEY não está no ambiente. Ver o cabeçalho deste Makefile."; exit 1; }
	@gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q . || { echo "erro: nenhuma conta gcloud ativa. Rode: gcloud auth login"; exit 1; }
	flutter pub get
	flutter build web --release \
		--dart-define=SUPABASE_URL="$$SUPABASE_URL" \
		--dart-define=SUPABASE_PUBLISHABLE_KEY="$$SUPABASE_PUBLISHABLE_KEY"
	@test ! -e build/web/assets/.env || { echo "erro: build/web/assets/.env existe. Alguém devolveu .env para assets: no pubspec.yaml — é o caminho do vazamento de 2026-08-10."; exit 1; }
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
