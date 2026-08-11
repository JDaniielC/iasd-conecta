## 1. Levantamento

- [ ] 1.1 Listar todas as colunas de `public.perfis` e classificar cada uma:
      gravável pela titular, ou não. Consultar `MAPA-DE-DADOS.md` — a
      classificação já existe lá para fins de LGPD e tem de bater
- [ ] 1.2 Procurar em `lib/` todo ponto que escreve em `perfis` (`.update(`,
      `.upsert(`, `.insert(`) e conferir contra a lista. Um ponto de escrita fora
      da lista é decisão a tomar antes da migration, não bug a descobrir depois

## 2. Migration

- [ ] 2.1 `revoke update on public.perfis from authenticated`, seguido de
      `grant update (<colunas graváveis>) on public.perfis to authenticated`
- [ ] 2.2 Comentário na migration explicando por que a lista é explícita, e que
      coluna nova nasce sem escrita — é a instrução para quem vier depois

## 3. Prova

- [ ] 3.1 Teste de integração como `authenticated`, com a sessão de uma pessoa
      comum: corrigir `nome` e `telefone` passa
- [ ] 3.2 Mesmo teste: escrever `idade` e escrever `genero` recusam com
      `permission denied`, e o valor anterior permanece
- [ ] 3.3 Rodar o fluxo de edição de Perfil do app contra o banco com a migration
      aplicada — nenhuma tela pode quebrar

## 4. Registro

- [ ] 4.1 Fechar o achado 5 de `SECURITY-AUDIT.md` e o § 2.1 de `PENDENCIAS.md`,
      com a data e o número dos testes que provaram
