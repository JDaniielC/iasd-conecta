# Specification Quality Checklist: Ação — encerramento, contagem de confirmados e clareza do título

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-08-09
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Constitution Alignment (Rede IASD)

- [x] Princípio I — termos do glossário (Ação, Ação candidata, Rodada de votação, Participar,
      Visitante, Usuário, Apelido, Dupla Missionária) usados exatos
- [x] Princípio II — declaração de dado pessoal presente; contagem é agregada, exibição de
      menor por Apelido preservada
- [x] Princípio IV — fila de espera, revogação, empate/descarte e Dupla Missionária
      declarados explicitamente, inclusive o que congela no encerramento
- [x] Princípio V — nenhum papel novo

## Notes

- Validado em 1 iteração, com 3 decisões resolvidas pelo usuário antes da escrita (nenhum
  `[NEEDS CLARIFICATION]` chegou ao arquivo):
  1. **Encerramento** = hora marcada + 4h (em vez de fim do dia, hora exata, ou campo de
     duração).
  2. **Ação encerrada** some da listagem, link direto continua válido e mostra quem
     participou.
  3. **Corrigir título de Ação já criada** fica fora do escopo — cancelar e recriar.
- **Divergência entre o reporte e o código, registrada de propósito na seção "Contexto
  observado" da spec**: o título "José Danilo Silva do Carmo" não é o nome de quem criou
  sendo exibido pelo app — as duas telas já exibem o nome da Ação. O dado é que está errado:
  esse texto foi digitado no campo "Nome da Ação". Por isso a US3 ataca o formulário de
  criação (orientação + validação), não a renderização do título. Se a intenção do usuário
  era outra, este é o ponto a revisitar em `/speckit-clarify`.
- Risco conhecido e aceito: a duração fixa de 4h cobre mal Ação de vários dias
  (acampamento). Registrado em Assumptions; a saída seria um campo de duração, adiado.
