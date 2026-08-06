# Quickstart: Exclusão de conta (009)

## Pré-requisitos

Mesmos das features anteriores — `supabase start` com a migration desta
feature aplicada (`supabase db reset`). Os cenários abaixo precisam de pelo
menos dois Administradores do distrito semeados (ver README, seção "Testando
manualmente", ou `scripts/bootstrap_admin.sh`).

Schema de referência: [`contracts/schema.sql`](./contracts/schema.sql).
Classificação dos vínculos: [`data-model.md`](./data-model.md).

## Como validar

```bash
supabase db reset          # aplica a migration desta feature
dart test test/integration/exclusao_de_conta_test.dart
flutter test test/widget/excluir_conta_page_test.dart
flutter test test/unit
flutter analyze
```

Os testes de integração **precisam** rodar como role `authenticated`, nunca
como superusuário — superusuário tem `BYPASSRLS` e não veria falha de
policy. Padrão já usado em `test/integration/security_nome_valido_rls_test.dart`.

## Cenários que provam a feature

Cada item abaixo mapeia para um Acceptance Scenario da
[spec](./spec.md). O que se afirma tem que ser verificado por consulta ao
banco depois da chamada, não por ausência de erro.

### US1 — sair sem deixar rastro

1. Perfil sem posse nenhuma chama `excluir_minha_conta()`. Conferir:
   `auth.users` não tem mais a linha; `perfis` **tem**, com
   `nome = 'Membro removido'` e `apelido`, `telefone`, `igreja_id`,
   `genero`, `idade` nulos; `anonimizado_em` preenchido.
2. `perfil_publico(uid)` devolve `nome_exibido = 'Membro removido'`. Este
   teste existe para travar o `coalesce(apelido, nome)` — sem ele, alguém
   "simplifica" a função depois e o nome antigo volta a aparecer.
3. Confirmação em Ação **passada** continua na tabela; confirmação em Ação
   **futura** sumiu.
4. Ação futura com `limite_vagas` cheio e alguém na fila: depois da
   exclusão, a pessoa da fila está com `status` de confirmada — provando que
   `confirmacoes_acao_promover_fila` disparou.

### US2 — herança sem derrubar o Grupo

5. Dona de Grupo com participantes exclui a conta. Conferir: o Grupo existe,
   `dono_id` é o Administrador mais antigo, e os participantes originais
   continuam lá.
6. **O caso que quebra se a ordem estiver errada**: o herdeiro *não*
   participava do Grupo antes. Depois da exclusão ele participa. Se a função
   trocar `dono_id` antes de inserir a participação,
   `grupos_dono_deve_participar` levanta exceção e a transação inteira
   desfaz — o teste falha alto, que é o desejado.
7. Rodada aberta por ela continua aberta, com `aberta_por` = herdeiro, e as
   candidatas e votos de outras pessoas intactos.
8. Rodada já fechada e Ações criadas por ela continuam com o id dela (agora
   anonimizado) — **não** trocam de autor.
9. Votos dela em Rodada aberta sumiram; votos em Rodada fechada ficaram.
10. Declaração de Líder/Diretor dela sumiu; declarações de outras pessoas em
    que ela consta como `confirmado_por` continuam válidas.
11. Ela era o Administrador mais antigo e existe outro: a herança vai para o
    segundo mais antigo.

### US3 — recusa

12. Único Administrador do distrito tenta excluir: exceção com mensagem
    sobre promover outro Administrador antes. Conferir que **nada** mudou —
    `perfis` intacto, `auth.users` intacto, `anonimizado_em` ainda nulo.
13. Mesmo caso, mas sem possuir Grupo nenhum: ainda assim recusa. É
    deliberado — um distrito sem Administrador não consegue promover outro.
14. Depois de promover um segundo Administrador, a mesma chamada conclui.

### Fluxo no app

15. Tela de exclusão não dispara nada sem confirmação explícita.
16. Depois do sucesso, o app chama `signOut()` e volta para o estado de
    Visitante. Sem isso o JWT já emitido segue válido até expirar e o app
    parece logado.
17. A mensagem de recusa aparece em português, explicando o que fazer, e não
    como erro cru do Postgres.

### Textos legais

18. Política de Privacidade e Termos de Uso não contêm mais a ressalva de
    que pode ser necessário transferir responsabilidades antes de sair
    (FR-016). Este é o item que fecha o buraco entre o que se promete e o
    que o código faz — vale conferir com `grep`, não de memória.
