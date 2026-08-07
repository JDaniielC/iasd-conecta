#!/usr/bin/env bash
# Cria (idempotente) o primeiro Administrador do distrito a partir do .env.
# Ver docs/plans/2026-08-04-bootstrap-admin-design.md.
# Requer: supabase start (ou stack self-hosted) já de pé e migrations aplicadas.
set -euo pipefail

env_file="${BOOTSTRAP_ENV_FILE:-.env}"
if [ -f "${env_file}" ]; then
  set -a
  # shellcheck disable=SC1091
  source "${env_file}"
  set +a
fi

: "${SUPABASE_URL:?defina SUPABASE_URL no .env}"
: "${SUPABASE_SERVICE_ROLE_KEY:?defina SUPABASE_SERVICE_ROLE_KEY no .env}"
: "${ADMIN_EMAIL:?defina ADMIN_EMAIL no .env}"
: "${ADMIN_SENHA:?defina ADMIN_SENHA no .env}"
: "${ADMIN_NOME:?defina ADMIN_NOME no .env}"
: "${ADMIN_GENERO:?defina ADMIN_GENERO no .env (masculino|feminino)}"
: "${ADMIN_IDADE:?defina ADMIN_IDADE no .env}"

auth_header=(-H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}")

# Idempotência via a mesma regra do trigger (migration
# 20260804120000_bootstrap_primeiro_admin.sql): só a primeira linha de
# administradores_distrito é bootstrap. Se já existe qualquer linha, não há
# o que fazer — não depende de filtro de listagem do GoTrue (não confiável
# entre versões: `GET /admin/users?email=` já foi observado ignorando o
# filtro e devolvendo o primeiro usuário da tabela toda).
ja_existe=$(curl -sS "${auth_header[@]}" \
  "${SUPABASE_URL}/rest/v1/administradores_distrito?select=usuario_id&limit=1" \
  | jq -r 'length > 0')

if [ "${ja_existe}" = "true" ]; then
  echo "bootstrap_admin: já existe Administrador do distrito, nada a fazer."
  exit 0
fi

create_response=$(curl -sS -w '\n%{http_code}' "${auth_header[@]}" -H "Content-Type: application/json" \
  -X POST "${SUPABASE_URL}/auth/v1/admin/users" \
  -d "$(jq -n --arg email "$ADMIN_EMAIL" --arg senha "$ADMIN_SENHA" \
    '{email: $email, password: $senha, email_confirm: true}')")
http_code=$(echo "${create_response}" | tail -n1)
create_body=$(echo "${create_response}" | sed '$d')

if [ "${http_code}" = "200" ] || [ "${http_code}" = "201" ]; then
  user_id=$(echo "${create_body}" | jq -r '.id')
elif [ "$(echo "${create_body}" | jq -r '.error_code // empty')" = "email_exists" ]; then
  # Recuperando de uma execução parcial anterior (ex.: script caiu entre
  # criar auth.users e inserir perfis/administradores_distrito). GET
  # /admin/users?email= não é confiável entre versões do GoTrue (não
  # filtra de verdade nesta imagem self-hosted), então busca a listagem
  # inteira e filtra no client.
  echo "bootstrap_admin: ${ADMIN_EMAIL} já tem auth.users, recuperando id e continuando." >&2
  user_id=$(curl -sS "${auth_header[@]}" "${SUPABASE_URL}/auth/v1/admin/users?per_page=1000" \
    | jq -r --arg e "${ADMIN_EMAIL}" '.users[] | select(.email == $e) | .id')
else
  echo "bootstrap_admin: falha ao criar auth.users para ${ADMIN_EMAIL} (http ${http_code}): ${create_body}" >&2
  exit 1
fi

if [ -z "${user_id}" ] || [ "${user_id}" = "null" ]; then
  echo "bootstrap_admin: não foi possível obter o id de ${ADMIN_EMAIL}: ${create_body}" >&2
  exit 1
fi

# Guardado como JSON (`null` ou `"uuid"` com aspas), não como texto cru:
# vai direto pro `--argjson` do jq lá embaixo.
igreja_id="null"
if [ -n "${ADMIN_IGREJA:-}" ]; then
  # -G/--data-urlencode em vez de interpolar na URL: nome de Igreja tem
  # espaço e acento ("Alto José Leal"), e curl não percent-encoda o que já
  # veio na URL — o request sai malformado e o lookup devolve nada.
  igreja_id=$(curl -sS -G "${auth_header[@]}" \
    --data-urlencode "nome=eq.${ADMIN_IGREJA}" \
    --data "select=id" \
    "${SUPABASE_URL}/rest/v1/igrejas" \
    | jq -c '.[0].id // null')
  if [ "${igreja_id}" = "null" ]; then
    echo "bootstrap_admin: Igreja '${ADMIN_IGREJA}' não existe no banco — confira o nome exato." >&2
    exit 1
  fi
fi

post_upsert() {
  local path="$1" body="$2"
  local response http_code
  response=$(curl -sS -w '\n%{http_code}' "${auth_header[@]}" -H "Content-Type: application/json" \
    -H "Prefer: return=minimal,resolution=merge-duplicates" \
    -X POST "${SUPABASE_URL}/rest/v1/${path}" -d "${body}")
  http_code=$(echo "${response}" | tail -n1)
  if [ "${http_code}" != "201" ] && [ "${http_code}" != "204" ]; then
    echo "bootstrap_admin: falha ao gravar em ${path} (http ${http_code}): $(echo "${response}" | sed '$d')" >&2
    exit 1
  fi
}

# O consentimento de vincular o Perfil a uma Igreja é destacado do
# consentimento geral (constraint `consentimento_igreja_destacado`, migration
# 20260724140000). Aqui ele é gravado porque quem roda o bootstrap preenche
# ADMIN_IGREJA para o próprio Perfil — é a pessoa consentindo por si mesma,
# não um terceiro sendo vinculado. Sem ADMIN_IGREJA, fica nulo dos dois lados.
post_upsert perfis "$(jq -n \
  --arg id "$user_id" --arg nome "$ADMIN_NOME" --arg genero "$ADMIN_GENERO" \
  --argjson idade "$ADMIN_IDADE" --argjson igreja_id "$igreja_id" \
  '{id: $id, nome: $nome, genero: $genero, idade: $idade, igreja_id: $igreja_id,
    consentimento_lgpd_aceito_em: (now | todate),
    consentimento_lgpd_igreja_aceito_em: (if $igreja_id == null then null else (now | todate) end)}')"

post_upsert administradores_distrito "$(jq -n --arg id "$user_id" '{usuario_id: $id, promovido_por: $id}')"

echo "bootstrap_admin: Administrador do distrito criado (${ADMIN_EMAIL}, id=${user_id})."
