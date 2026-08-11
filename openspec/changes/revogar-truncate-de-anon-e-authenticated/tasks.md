## 1. Levantamento

- [ ] 1.1 Listar as tabelas de `public` com os três privilégios ainda
      concedidos a `anon`/`authenticated`, e anotar **o número** — é o antes
- [ ] 1.2 Anotar a contagem atual das três suítes, para comparar depois

## 2. Migration

- [ ] 2.1 `revoke truncate, references, trigger on all tables in schema public
      from anon, authenticated`
- [ ] 2.2 `alter default privileges in schema public revoke ...` para que tabela
      nova nasça fechada
- [ ] 2.3 Comentário registrando por que TRUNCATE importa aqui: ignora RLS e não
      dispara gatilho `after delete` — foi o que a feature 013 mediu

## 3. Prova

- [ ] 3.1 Como `authenticated`, `truncate` em três tabelas de natureza diferente
      (uma com RLS de leitura pública, uma com gatilho, uma de junção) recusa
- [ ] 3.2 Criar tabela de teste numa transação revertida e conferir que ela
      nasce **sem** os privilégios
- [ ] 3.3 Rodar as três suítes e comparar com o número de 1.2 — igual, não
      "passou"

## 4. Registro

- [ ] 4.1 Fechar `PENDENCIAS.md` § 2.2 com a data e os números
