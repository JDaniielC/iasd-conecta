# Specification Quality Checklist: Arquivar Grupo

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

- [x] Princípio I — termos do glossário exatos (Grupo, Ação, Ação candidata, Rodada de
      votação, Participar, Dono do Grupo, Ministério, Líder/Diretor, Administrador do
      distrito, Dupla Missionária). Dois termos **novos** (Arquivar o Grupo, Grupo arquivado)
      exigem entrada em `CONTEXT.md` antes do código — virou FR-023
- [x] Princípio II — declarado: nenhum dado pessoal novo; a feature **reduz** exposição, porque
      o Ministério arquivado deixa de exibir publicamente o Líder/Diretor
- [x] Princípio IV — **quatro das cinco regras centrais são tocadas** e todas estão declaradas:
      fila de espera, desempate, descarte de candidatas, revogação de Participar. Dupla
      Missionária declarada como inalterada
- [x] Princípio V — nenhum papel novo

## Notes

- Validado em 1 iteração. Três decisões resolvidas com o usuário antes da escrita, nenhum
  `[NEEDS CLARIFICATION]` chegou ao arquivo:
  1. **Ações futuras são canceladas junto**, com a contagem do estrago mostrada antes.
  2. **Arquivar, não apagar** — o Grupo sai das listas, o histórico fica, o Administrador
     reverte.
  3. **Dono e Administrador arquivam, sem exceção** — inclusive Ministério com Líder/Diretor
     confirmado.

- **O pedido foi "deletar", a entrega é "arquivar".** Está no topo da spec e em Assumptions.
  Motivo: `rodadas_votacao.grupo_id`, `acoes.grupo_id` e `liderancas.grupo_id` são FK **sem**
  `on delete`, então o banco já recusa apagar um Grupo com qualquer histórico. Não é limitação
  a contornar — é proteção deliberada do que outras pessoas construíram, no mesmo espírito da
  feature 009. Se a intenção era mesmo remover do banco, a spec precisa ser refeita.

- **A decisão mais discutível da spec foi tomada sem consulta**: Rodada de votação aberta é
  encerrada **sem apuração**, descartando todas as candidatas (FR-007). A alternativa — apurar
  e criar uma Ação vencedora dentro de um Grupo que acabou de ser arquivado — não tem leitura
  sensata. Está em Assumptions marcada como tal, e é o primeiro ponto a revisitar em
  `/speckit-clarify`.

- **A consequência mais dura, registrada de propósito**: desarquivar **não** ressuscita as
  Ações canceladas nem as Rodadas encerradas. Um Grupo arquivado por engano na véspera de uma
  Ação com 12 presenças confirmadas destrói aquele encontro de forma irreversível. FR-003 e
  FR-022 existem só para que ninguém descubra isso depois.

- **Ninguém é avisado.** Quem participava e quem tinha presença confirmada não recebe
  notificação — o app não tem esse canal. As pessoas descobrem ao abrir o app. Está em
  Assumptions.

- Esta feature **não** cria exclusão definitiva de Grupo. Consequência: o FR-021 da feature
  `013-foto-de-capa` continua descrevendo um evento que não acontece.
