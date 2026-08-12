## Why

`anon` e `authenticated` herdam `TRUNCATE`, `REFERENCES` e `TRIGGER` em todas as
tabelas de `public` — default do fornecedor, nunca concedido por este projeto.

**`TRUNCATE` ignora RLS por completo e não dispara gatilho `after delete`.**

Não é porta aberta hoje: `anon` é `rolcanlogin = f` e só é alcançável via
PostgREST, que mapeia verbo HTTP para SELECT/INSERT/UPDATE/DELETE e nunca emite
TRUNCATE. É desvio de menor privilégio, não vulnerabilidade viva.

O que mudou em 2026-08-10 é a **consequência**. A feature 013 tornou concreto o
dano: uma única instrução apagaria todas as linhas de `fotos_capa` sem enfileirar
nada, e todos os arquivos do bucket virariam órfãos de uma vez — o desenho
inteiro da feature caindo por uma porta que ela não abriu. A 013 fechou as suas
duas tabelas. **As outras 14 continuam abertas**, e agora se sabe que a
consequência de cada uma depende do que ela sustenta.

`PENDENCIAS.md` § 2.2.

## What Changes

`revoke truncate, references, trigger` de `anon` e `authenticated` em todas as
tabelas de `public`, e nas que vierem depois.

Nada mais muda. Nenhum caminho legítimo do app emite TRUNCATE — e a tarefa que
importa nesta change é **provar isso**, não afirmá-lo.

## Capabilities

### New Capabilities
- `privilegios-de-banco`: o piso de privilégio dos papéis públicos do banco —
  o que `anon` e `authenticated` podem fazer antes de qualquer policy filtrar.

## Impact

- `supabase/migrations/` — uma migration.
- Nenhuma mudança em `lib/`. Se algo quebrar, quebra na suíte de integração, que
  é onde os caminhos reais são exercitados.
