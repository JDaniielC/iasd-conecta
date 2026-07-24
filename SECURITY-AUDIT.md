# Auditoria de segurança — RLS/autorização (2026-07-24)

Auditoria ponta a ponta de RLS, `SECURITY DEFINER` e regras de negócio
across as 8 features (001-008), pedida depois do domínio central estar
completo. 3 bugs críticos confirmados por reprodução direta via
`docker exec -i supabase_db_iasd psql` (não só leitura de código) e
corrigidos em `supabase/migrations/20260724130000_fix_rls_security_bugs.sql`.

## Bug 1 — cadastro real quebrado desde a feature 001

`nome_valido()` (`20260723191202_perfis_igrejas.sql`) lê
`palavras_bloqueadas` sem ser `SECURITY DEFINER`, e a tabela nunca
recebeu `GRANT SELECT` pra `anon`/`authenticated`. Todo `INSERT` real em
`perfis` (cadastro de Perfil) — que dispara o `CHECK (nome_valido(nome))`
como parte da transação do próprio usuário — falhava com `permission
denied for table palavras_bloqueadas`.

**Por que passou despercebido**: todo teste de integração que semeia
`perfis` (`criarPerfilDeTeste` em `db_test_helper.dart`, e o teste
dedicado de `nome_valido`) insere direto como superusuário Postgres, que
ignora `GRANT` — nenhum teste jamais exercitou o caminho real de
cadastro como role `authenticated`. 7 features inteiras (002-008) foram
implementadas e testadas em cima de uma feature 001 cujo cadastro nunca
funcionaria de verdade fora dos testes.

**Reprodução** (antes do fix): `insert into perfis (...)` como
`authenticated` → `ERROR: permission denied for table
palavras_bloqueadas`.

**Fix**: `grant select on public.palavras_bloqueadas to anon,
authenticated;`

**Teste de regressão**: `test/integration/security_signup_grant_test.dart`

## Bug 2 — Ação de Grupo forjada sem participação nem votação

`acoes_candidata_checar_regras()` (`20260724084300_rodada_votacao.sql`)
só valida participação/rodada quando `new.rodada_id is not null` —
retorna cedo (`return new`) sem tocar em `grupo_id` quando `rodada_id` é
nulo. A policy `acoes_insert_criador` só checa `auth.uid() =
criador_id`, nunca restringe `grupo_id`. Como `confirmada` nasce `true`
por default, qualquer `authenticated` conseguia inserir uma Ação de
Grupo já "confirmada" em **qualquer** Grupo do distrito, sem nunca ter
participado dele nem existir voto algum — violando a definição do
próprio domínio (`CONTEXT.md`: "Ação de Grupo nasce como Ação
candidata").

**Reprodução** (antes do fix): usuário sem nenhuma linha em
`participacoes_grupo` do Grupo alvo insere `acoes (nome, ..., criador_id,
grupo_id)` com `rodada_id` omitido → sucesso, `confirmada = true`.

**Fix**: `grupo_id` só é permitido junto de `rodada_id` — Ação de Grupo
sempre nasce candidata; tentativa de `grupo_id` sem `rodada_id` levanta
exceção.

**Teste de regressão**: `test/integration/security_acao_grupo_sem_rodada_test.dart`

## Bug 3 — candidata auto-confirmada pelo criador, sem votação

As 3 versões sucessivas da policy de `UPDATE` de `acoes`
(003→004→005) nunca tiveram `WITH CHECK` explícito — Postgres reusa
`USING` (que só verifica identidade, não os valores da linha nova).
Qualquer criador de uma candidata ainda em votação conseguia rodar
`update acoes set confirmada = true where id = <minha_candidata>`
direto via PostgREST, bypassando inteiramente `fechar_rodada_se_devido`
(apuração, desempate por sorteio, descarte das perdedoras).

**Reprodução** (antes do fix): criador de uma candidata com `rodada_id`
ainda aberta roda `UPDATE ... SET confirmada = true` na própria linha →
sucesso imediato, sem nenhum voto.

**Fix**: trigger `BEFORE UPDATE` (`acoes_protege_campos_internos`)
bloqueia mudança direta em `confirmada`/`grupo_id`/`rodada_id`/
`criador_id`, a menos que a GUC de transação `app.bypass_acoes_protecao`
esteja setada como `'true'` — só `fechar_rodada_se_devido` (o único
caminho legítimo) seta essa flag antes do seu próprio `UPDATE` interno.

**Teste de regressão**: `test/integration/security_acoes_protege_campos_test.dart`
(cobre tanto a rejeição do criador quanto a confirmação de que o
caminho interno legítimo continua funcionando).

## Verificação

- Todos os 3 bugs reproduzidos empiricamente via psql ANTES do fix, e
  reconfirmados como corrigidos DEPOIS, na mesma sessão.
- Regressão checada manualmente: Ação avulsa (sem grupo/rodada) continua
  funcionando; cancelar Ação (`cancelada_em`) continua funcionando;
  `fechar_rodada_se_devido` continua apurando e confirmando a vencedora.
- `flutter test`: 171/171 passando (4 novos testes de regressão).
- `flutter analyze`: sem apontamentos.

## O que a auditoria NÃO encontrou (verificado e descartado)

- Nenhum outro `CHECK constraint` com comparação contra `NULL` sem guarda
  explícita (além dos 2 já corrigidos nas features 006/007 durante o
  desenvolvimento normal).
- Nenhuma função `SECURITY DEFINER` sem `search_path` fixado.
- Nenhum vazamento de `idade` ou nome real de menor de idade —
  `perfil_publico()` e a RLS de `perfis` seguram isso corretamente.
- `grupos_update_dono`'s `WITH CHECK (true)` é seguro porque o trigger
  `checar_dono_participa` independentemente bloqueia a troca de dono pra
  quem não participa — padrão já correto desde a feature 002.
