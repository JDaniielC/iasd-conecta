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
# ---------------------------------------------------------------------
# 🔴 A ÁRVORE PRECISA TER PROVA DE CI VERDE — OU CONFIRMAÇÃO EXPLÍCITA
# ---------------------------------------------------------------------
# openspec/changes/travar-deploy-com-teste-vermelho: até aqui este alvo não
# rodava teste nenhum — só compilava e publicava. Fechar isso rodando a suíte
# inteira AQUI foi medido e descartado: `flutter analyze` + `flutter test
# test/unit test/widget` + `dart test test/integration` (com Supabase local já
# de pé) levou ~20s de parede nesta máquina — o tempo não é o problema. O
# problema é o que isso exigiria: gerenciar o ciclo de vida do Supabase local
# (subir/derrubar Docker) DENTRO de um alvo de publicação arrisca matar uma
# sessão de desenvolvimento já em andamento na mesma máquina (`supabase stop`
# no meio de outro `flutter run`), e ainda assim só provaria o código contra o
# Postgres local — não o commit exato que será publicado, se a árvore tiver
# mudança não commitada.
#
# Em vez disso, este alvo pergunta ao GitHub se o `ci.yml` já aprovou o commit
# exato do HEAD em `main` — a mesma prova de que `deploy-web.yml` agora
# depende (`workflow_run`). Duas recusas:
#   - árvore de trabalho suja (mudança não commitada): o CI não pode ter
#     provado o que não foi commitado;
#   - HEAD sem execução `success` de `ci.yml` encontrada via `gh run list`.
# As duas têm escape: `CONFIRM_SEM_PROVA=sim make deploy-web ...` publica
# mesmo assim, com aviso — para o caso real de publicar de propósito antes do
# CI terminar, ou sem `gh` autenticado à mão.
CONFIRM_SEM_PROVA :=

# Pré-requisitos, uma vez por máquina/pessoa:
#   1. gcloud auth login   — com a conta que tem roles/storage.objectAdmin no bucket
#                             e roles/compute.loadBalancerAdmin no projeto
#   1b. gh auth login      — para este alvo checar se o ci.yml do commit está verde
#   2. as DUAS chaves públicas de produção no ambiente:
#        export SUPABASE_URL=https://<project-ref>.supabase.co
#        export SUPABASE_PUBLISHABLE_KEY=<chave publicável de produção>
#      NUNCA exporte SUPABASE_SERVICE_ROLE_KEY nem ADMIN_* aqui: o que entra em
#      --dart-define entra no JavaScript publicado, legível por qualquer pessoa.
#
# Numa linha só, sem exportar nada na sessão:
#   SUPABASE_URL=https://<project-ref>.supabase.co \
#   SUPABASE_PUBLISHABLE_KEY=<chave publicável de produção> \
#   make deploy-web
#
# 🔴 NÃO faça `source .env`: o `.env` deste repositório aponta para
# http://127.0.0.1:54321, e o deploy publicaria o site de produção falando com o
# Docker de quem publicou — sem erro nenhum na publicação. Há uma guarda abaixo
# para isso, mas a guarda é a segunda linha de defesa, não a primeira.
PROJECT := iasd-505120
BUCKET := gs://conecta-iasd-site
URL_MAP := conecta-iasd-site-url-map
ASSET_CACHE_CONTROL := public, max-age=3600
HTML_CACHE_CONTROL := no-cache, max-age=0, must-revalidate

deploy-web:
	@test -n "$$SUPABASE_URL" || { echo "erro: SUPABASE_URL não está no ambiente. Ver o cabeçalho deste Makefile."; exit 1; }
	@test -n "$$SUPABASE_PUBLISHABLE_KEY" || { echo "erro: SUPABASE_PUBLISHABLE_KEY não está no ambiente. Ver o cabeçalho deste Makefile."; exit 1; }
	@case "$$SUPABASE_URL" in \
		*127.0.0.1*|*localhost*|*host.docker.internal*) \
			echo "erro: SUPABASE_URL aponta para o ambiente local ($$SUPABASE_URL)."; \
			echo "       Isso publicaria o site de produção falando com o seu Docker — e o"; \
			echo "       deploy não daria erro nenhum; só quem abrisse o site veria."; \
			echo "       Provável causa: 'source .env'. Use a URL de produção."; \
			exit 1 ;; \
	esac
	@if [ "$$CONFIRM_SEM_PROVA" = "sim" ]; then \
		echo "⚠️  Publicando SEM checar prova de CI verde — confirmado explicitamente (CONFIRM_SEM_PROVA=sim)."; \
	else \
		if [ -n "$$(git status --porcelain)" ]; then \
			echo "erro: a árvore de trabalho tem mudança não commitada. O ci.yml só prova o que"; \
			echo "       foi commitado — commite antes, ou publique sem prova com"; \
			echo "       CONFIRM_SEM_PROVA=sim make deploy-web ..."; \
			exit 1; \
		fi; \
		command -v gh >/dev/null 2>&1 || { \
			echo "erro: gh (GitHub CLI) não encontrado — não dá para checar se o ci.yml passou"; \
			echo "       para este commit. Instale e rode 'gh auth login', ou publique sem prova"; \
			echo "       com CONFIRM_SEM_PROVA=sim make deploy-web ..."; \
			exit 1; \
		}; \
		SHA="$$(git rev-parse HEAD)"; \
		CONCLUSION="$$(gh run list --workflow=ci.yml --branch main --limit 20 \
			--json headSha,conclusion,status \
			--jq ".[] | select(.headSha==\"$$SHA\" and .status==\"completed\") | .conclusion" \
			2>/dev/null | head -1)"; \
		if [ "$$CONCLUSION" != "success" ]; then \
			echo "erro: commit $$SHA não tem execução de ci.yml com sucesso confirmada em main"; \
			echo "       (achei: '$${CONCLUSION:-nenhuma execução}'). Espere o CI terminar"; \
			echo "       ('gh run list --workflow=ci.yml --branch main'), ou publique sem prova"; \
			echo "       com CONFIRM_SEM_PROVA=sim make deploy-web ..."; \
			exit 1; \
		fi; \
		echo "ci.yml confirmado verde em main para $$SHA."; \
	fi
	@echo "Publicando contra $$SUPABASE_URL"
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
	gcloud compute url-maps invalidate-cdn-cache $(URL_MAP) --project=$(PROJECT) --path "/*"
	@echo "Publicado. Site: http://8.233.229.106/ (IP do load balancer, que é o mesmo que https://conecta-iasd.site/)"
