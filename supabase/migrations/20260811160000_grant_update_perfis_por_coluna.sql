-- Achado 5 de SECURITY-AUDIT.md / PENDENCIAS.md § 2.1, change
-- `endurecer-grant-update-perfis`.
--
-- `20260723191202_perfis_igrejas.sql:56` concedeu `update` na tabela inteira
-- a `authenticated`. A policy `perfis_update_own` protege a LINHA — ninguém
-- altera Perfil alheio — mas nunca protegeu a COLUNA. Por chamada direta à
-- API, fora de qualquer tela, a própria titular escrevia a própria `idade` e
-- o próprio `genero`. Não é vazamento (é dado dela), é contorno de regra de
-- domínio: `idade` sustenta a exigência de Apelido e autorização de
-- responsável para menor de 13 (feature 015); `genero` sustenta a composição
-- de Dupla Missionária (`confirmacoes_acao_decidir_status()`).
--
-- `revoke` + `grant update (colunas)`, não uma policy com `with check`: a
-- policy compararia `old`/`new` e recusaria a mudança, mas isso duplicaria em
-- SQL de policy uma regra que o `grant` de coluna já resolve nativamente — e
-- a recusa por `grant` vem antes da policy sequer rodar. Menos código, mesma
-- garantia.
--
-- A LISTA É EXPLÍCITA E NOMEADA DE PROPÓSITO, NÃO DERIVADA. É o padrão que
-- falha para o lado seguro: coluna nova em `public.perfis` nasce SEM
-- permissão de escrita para `authenticated`, e quem a acrescentar precisa
-- decidir conscientemente incluí-la aqui. Se você acabou de rodar um `alter
-- table public.perfis add column ...` e a tela precisa que a titular
-- escreva essa coluna, adicione-a ao `grant` abaixo — numa migration nova,
-- não editando esta.
--
-- As cinco colunas abaixo são exatamente as que `Profile.toUpdateMap()`
-- manda (`lib/features/profile/domain/profile.dart:189-198`, único ponto de
-- `.update()` em `perfis` como usuário comum,
-- `lib/features/profile/data/profile_repository.dart:50`). `idade` e
-- `genero` ficam de fora — é o requirement central desta change.
-- `consentimento_lgpd_aceito_em`, `consentimento_lgpd_versao`,
-- `consentimento_lgpd_igreja_versao`, `responsavel_*` e
-- `autorizacao_responsavel_*` também ficam de fora: são carimbadas só pelo
-- gatilho `perfis_carimbar_consentimento` (`before insert or update`,
-- `security invoker`), e um gatilho `NEW.coluna := valor` não é bloqueado
-- por `grant update` de coluna — o grant restringe a cláusula `SET`
-- explícita do cliente, não a reescrita do gatilho. `public.excluir_minha_conta`
-- (`security definer`) também não é afetada: roda como o dono da função,
-- que tem privilégio de tabela inteira.
revoke update on public.perfis from authenticated;

grant update (nome, apelido, igreja_id, telefone,
              consentimento_lgpd_igreja_aceito_em)
  on public.perfis to authenticated;
