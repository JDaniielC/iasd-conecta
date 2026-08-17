## Why

A capability `suite-de-integracao` já declara o que a suíte garante sobre si
mesma, e já declara a dívida: *"as 48 continuam existindo. Unificá-las é
varredura de risco próprio ... O que esta requirement proíbe a partir de hoje é
a 49ª."* Essa permissão era para não consertar **agora**, não para deixar
crescer.

**A janela deixou de ser hipotética em 2026-08-17.** Fechando `mensagem-fixada`,
`dart test test/integration` falhou em **duas de três execuções** no
`tearDownAll` de `convite_nao_reserva_vaga_test.dart`, com FK de `perfis` e
linha já apagada. Causa: `chat_denuncias_do_grupo_test.dart` usava os **mesmos
três uids**. Um par foi consertado na hora; **restam 16**
(`PENDENCIAS.md` 2.21).

As outras duas frentes têm a mesma forma — estado compartilhado que ninguém
declarou:

- **16 das 48 cópias locais de `asUser` não devolvem `request.jwt.claims`**
  (2.20, medido em 2026-08-16). `reset role` não limpa GUC customizado, então o
  papel seguinte ainda enxerga a identidade anterior. O comentário que explica
  isso mora dentro de UMA das 32 que acertam, onde as outras 47 não o leem.
- **A eleição de herdeiro alcança Administrador de outro arquivo** (2.7,
  achado no laço de 30 execuções em 2026-08-11). `administradores_distrito` é
  global, e `excluir_minha_conta` decide pela contagem. `createTestDistrictAdmin`
  já toma lock consultivo por causa disso; a eleição de herdeiro não.

O custo de não consertar não é o tempo perdido relendo um teste vermelho — é
que a suíte deixa de ser prova. Uma falha intermitente é descartada como flake,
e a próxima falha real é descartada junto.

## What Changes

- Cada arquivo da suíte passa a ter **identidade própria**, sem uid repetido
  entre arquivos.
- As 48 cópias locais de "usuário autenticado" viram a definição compartilhada
  que já existe, e as 16 que esqueciam de devolver a identidade param de
  existir.
- O estado global que a suíte disputa passa a ser **declarado e serializado**,
  não descoberto por falha — `administradores_distrito` na eleição de herdeiro,
  como já é na criação.
- Uma verificação que **falha** quando alguém reintroduz uid repetido ou
  escreve a 49ª cópia. Sem isso, o conserto dura até a próxima change.

**Nenhuma mudança em código de produção.** Nada aqui altera schema, policy ou
tela.

## Capabilities

### New Capabilities
Nenhuma.

### Modified Capabilities
- `suite-de-integracao`: "A suíte é determinística em paralelo" ganha a
  exigência de identidade própria por arquivo e de estado global declarado;
  "Cada papel de teste tem uma definição só" perde a permissão de dívida — as
  cópias deixam de ser toleradas — e ganha a exigência de que a regra seja
  verificável por máquina.

## Impact

**Independente das outras três changes.** Toca só `test/`. Se rodar em paralelo
com elas, o conflito é textual (arquivos de teste que as outras criam), não
semântico — e a ordem recomendada é esta **por último**, para os testes novos
já nascerem certos.

**Código de teste** — 48 arquivos com cópia local de `asUser`, e ~16 arquivos
que precisam trocar de prefixo de uid.

**Nenhum dado pessoal. Nenhum efeito legal. Nenhuma Novidade** — é exatamente
o que o `CRITERIO-DE-NOVIDADE.md` manda deixar de fora.

**Ledgers** — `PENDENCIAS.md` 2.21, 2.20 e 2.7.

**Risco próprio, e é o motivo de ela ter sido adiada duas vezes:** mexer em 48
arquivos de teste pode quebrar testes por motivo que não é o deles. A prova de
que deu certo é a própria suíte, rodada em laço — e o número de execuções
precisa ser grande o bastante para uma janela de uma em trinta aparecer.
