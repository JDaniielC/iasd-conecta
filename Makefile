.PHONY: deploy-web coverage coverage-full
# ---------------------------------------------------------------------
# COBERTURA — o piso que a árvore não pode furar
# ---------------------------------------------------------------------
# Constituição, Princípio IV (inegociável, 1.2.0): a cobertura de linha dos
# testes de unidade e de widget é medida por um comando único, versionado, que
# reprova quando o número cai abaixo do piso registrado.
#
# 🔴 A SUÍTE VERMELHA NÃO REPORTA COBERTURA, DE PROPÓSITO
# Um `lcov.info` de execução parcial produz percentual ALTO — o que não rodou
# não conta como não coberto — e passaria o gate numa árvore quebrada. Por isso
# `flutter test --coverage` vem primeiro e `make` aborta a receita se ele sair
# diferente de zero, antes de qualquer medição.
#
# 🔴 O QUE FICA FORA DO DENOMINADOR, E POR QUÊ
# A lista mora em scripts/coverage_summary.dart (isExcluded), com o motivo em
# comentário ao lado de cada entrada. Hoje são duas:
#   - lib/features/*/data/  — a camada de repositório é provada por
#     `dart test test/integration`, que roda contra Postgres e não entra nesta
#     medição. Mantê-la no denominador faria o número medir a ausência da
#     integração, não a cobertura do código.
#
#     UMA EXCEÇÃO DENTRO DA EXCEÇÃO, e o motivo escrito precisa dizê-la:
#     `action/data/actions_seen_repository.dart` cai neste padrão mas NÃO fala
#     com o Supabase — é SharedPreferences, e quem o prova é
#     `test/unit/actions_seen_repository_test.dart`, que roda DENTRO desta
#     medição. O padrão descarta as linhas dele mesmo estando cobertas, então o
#     número reportado é levemente MENOR que a realidade. Errar para baixo é o
#     lado certo de errar num piso; estreitar o padrão para salvar um arquivo
#     de 20 linhas custaria mais do que rende.
#
# É a ÚNICA. `lib/main.dart` já esteve aqui e saiu na convergência C1.3: a
# requirement recusa excluir código que nenhuma suíte prova, e nenhuma prova o
# main. A exclusão também não mudava número — ele nem chega ao lcov.
#
# NÃO estão excluídos, e é deliberado:
#   lib/features/chat/domain/chat_limits.dart e
#   lib/features/legal/legal_metadata.dart. Estavam fora do lcov só porque
#   nenhum teste os importava. São constantes que a regra usa, e o caminho certo
#   é um teste importá-los — não o gate ignorá-los. Desde a change
#   `cobertura-e-tdd` há teste de unidade que os importa, e eles contam.
#
# 🔴 O PISO SOBE, E NÃO DESCE
# Medido em 2026-08-20 sobre o denominador acima, ao fim da change
# `cobertura-e-tdd`: 3511/4131 = 85,0%, estável em três execuções seguidas.
#
# O piso fica em 84.5, e não em 85.0, por um motivo medido e não por
# conservadorismo genérico: durante a change o mesmo comando deu 2980/4131 numa
# execução e 2990/4131 nas três seguintes, sem uma linha de lib/ ter mudado —
# 0,24pp de variação. A causa não foi perseguida. A folga de 0,5pp absorve essa
# ordem de grandeza, porque um gate que reprova sozinho é pior que gate nenhum:
# ensina a ignorá-lo, e aí ele deixa de funcionar quando importa.
#
# Quando o gate reprovar, o conserto é escrever o teste que falta. Baixar este
# número exige motivo escrito no corpo do commit — remoção deliberada de código
# testado, por exemplo. O piso é o registro do que já esteve provado.
COVERAGE_FLOOR := 84.5

coverage:
	flutter test --coverage test/unit test/widget
	@dart run scripts/coverage_summary.dart --floor $(COVERAGE_FLOOR)

# ---------------------------------------------------------------------
# COBERTURA COMPLETA — o número sem exclusão, NÃO É GATE
# ---------------------------------------------------------------------
# openspec/changes/afirmar-sem-conferir, Decisão 5: `coverage` mede o que roda
# sem banco, e exclui `lib/features/*/data/` por isso (ver o cabeçalho de
# `coverage`, acima). Este alvo mede o projeto INTEIRO, sem exclusão — soma o
# `lcov` de `flutter test test/unit test/widget` com o de
# `dart test test/integration --coverage-path`, e reporta sobre os dois
# juntos com `scripts/coverage_summary.dart --no-exclusions`.
#
# 🔴 NÃO ENTRA NO ci.yml, E O NÚMERO NÃO SE COMPARA COM COVERAGE_FLOOR
# São denominadores diferentes: este inclui `lib/main.dart` e a camada de
# repositório inteira, que quase não é exercitada por linha — os testes de
# integração falam com o Postgres por `package:postgres`/`package:supabase`
# direto, sem passar pelas classes `*Repository` de `lib/`, então a camada de
# dados fica majoritariamente descoberta mesmo aqui. Um número baixo aqui é
# esperado e não é regressão do gate rápido. Virar gate exigiria o ciclo de
# vida do Supabase local dentro do CI — custo já medido e recusado para
# `deploy-web` (ver o comentário daquele alvo, mais abaixo).
#
# 🔴 REQUER O SUPABASE LOCAL, E `dart test test/integration` FALA COM UM
# POSTGRES COMPARTILHADO — leia a seção "Testes de integração" do CLAUDE.md
# antes de rodar isto com outro agente/sessão ativo na mesma máquina.
coverage-full:
	@command -v supabase >/dev/null 2>&1 || { echo "erro: supabase CLI não encontrado. Rode 'supabase start' à mão primeiro."; exit 1; }
	@supabase status >/dev/null 2>&1 || supabase start
	flutter test --coverage test/unit test/widget
	dart test test/integration --coverage-path=coverage/integration_lcov.info
	dart run scripts/coverage_summary.dart --no-exclusions \
		--lcov coverage/lcov.info --lcov coverage/integration_lcov.info


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
