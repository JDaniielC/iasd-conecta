#!/usr/bin/env bash
# Verificação ponta a ponta da drenagem de capas (feature 013, T046).
#
# Prova o elo que TODOS os testes automatizados deixam de fora: fila ->
# Edge Function -> objeto fora do bucket. Os testes param em "o caminho foi
# enfileirado", porque exercitar isto exige a Edge Function de pé, e ela não
# sobe no CI.
#
# Uso, com `supabase start` já rodando:
#
#   supabase functions serve drenar-capas &      # deixe rodando
#   ./specs/013-foto-de-capa/scripts/verificar-drenagem.sh
#
# Resultado esperado: OBJETOS ANTES 1, OBJETOS DEPOIS 0, e removido_em
# preenchido em poucos segundos.
set -euo pipefail

CAMINHO="grupo/verificacao-drenagem/objeto.jpg"
PSQL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
CHAVE=$(supabase status -o json | python3 -c "import sys,json; print(json.load(sys.stdin)['SERVICE_ROLE_KEY'])")

printf '\xFF\xD8\xFF\x00' > /tmp/capa-verificacao.jpg
curl -s -o /dev/null -w 'UPLOAD: HTTP %{http_code}\n' \
  -X POST "http://127.0.0.1:54321/storage/v1/object/fotos-capa/${CAMINHO}" \
  -H "Authorization: Bearer ${CHAVE}" \
  -H "Content-Type: image/jpeg" \
  --data-binary @/tmp/capa-verificacao.jpg

echo -n 'OBJETOS ANTES: '
psql "$PSQL" -tAc "select count(*) from storage.objects where bucket_id='fotos-capa' and name='${CAMINHO}'"

psql "$PSQL" -q -c "insert into public.capas_a_remover (caminho) values ('${CAMINHO}') on conflict do nothing"
psql "$PSQL" -q -c "select public.drenar_capas_a_remover()"
echo 'DRENAGEM PEDIDA — aguardando'
sleep 5

echo -n 'REMOVIDO_EM: '
psql "$PSQL" -tAc "select coalesce(removido_em::text,'(ainda nulo)') from public.capas_a_remover where caminho='${CAMINHO}'"
echo -n 'OBJETOS DEPOIS: '
psql "$PSQL" -tAc "select count(*) from storage.objects where bucket_id='fotos-capa' and name='${CAMINHO}'"

psql "$PSQL" -q -c "delete from public.capas_a_remover where caminho='${CAMINHO}'"
rm -f /tmp/capa-verificacao.jpg
