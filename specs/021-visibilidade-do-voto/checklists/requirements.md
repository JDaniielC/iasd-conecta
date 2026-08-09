# Specification Quality Checklist: Quem pode ver em quem você votou

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-08-09
**Feature**: [spec.md](../spec.md)

## Content Quality

- [X] No implementation details (languages, frameworks, APIs)
- [X] Focused on user value and business needs
- [X] Written for non-technical stakeholders
- [X] All mandatory sections completed

Nota sobre o primeiro item: o Contexto cita SQL e Dart existentes. É citação do estado
atual — a evidência de que o problema existe —, não prescrição de como resolvê-lo. Nenhum
requisito nomeia mecanismo: FR-005 diz "garantida no banco" porque a diferença entre banco
e tela **é** o problema desta feature, não uma escolha técnica.

## Requirement Completeness

- [X] No [NEEDS CLARIFICATION] markers remain
- [X] Requirements are testable and unambiguous
- [X] Success criteria are measurable
- [X] Success criteria are technology-agnostic (no implementation details)
- [X] All acceptance scenarios are defined
- [X] Edge cases are identified
- [X] Scope is clearly bounded
- [X] Dependencies and assumptions identified

Nota sobre os marcadores: a decisão de alcance ("só o próprio voto" versus "os
participantes do Grupo") **não** virou `[NEEDS CLARIFICATION]`. Ela tem um padrão
defensável, está registrada como Assumption com as três razões, e a spec diz explicitamente
qual linha muda se a escolha for a outra. Marcar teria bloqueado o planejamento por uma
decisão que `/speckit-clarify` resolve em uma resposta.

## Feature Readiness

- [X] All functional requirements have clear acceptance criteria
- [X] User scenarios cover primary flows
- [X] Feature meets measurable outcomes defined in Success Criteria
- [X] No implementation details leak into specification

## Cobertura FR → SC

| FR | Coberto por |
|---|---|
| FR-001 Visitante não lê voto | SC-001 |
| FR-002 Usuário de fora não lê | SC-002 |
| FR-003 lê o próprio | SC-003 |
| FR-004 não lê o de terceiro | SC-002 |
| FR-005 garantido no banco | SC-001 (consulta direta à API, não tela) |
| FR-006 vale após fechar | SC-001, SC-002 |
| FR-007 registrar voto | SC-004 |
| FR-008 trocar de voto | SC-004 |
| FR-009 apuração conta tudo | SC-005 |
| FR-010 tela marca a escolhida | SC-003 |
| FR-011 desempate intacto | SC-005 |
| FR-012 Política corrigida | SC-006 |
| FR-013 MAPA-DE-DADOS corrigido | SC-006 |
| FR-014 decisão registrada | SC-006 |

14/14 requisitos com critério de sucesso associado.

## Notes

- A armadilha desta feature está no Edge Case do `upsert`: fechar a **leitura** pode
  quebrar a **escrita** de quem troca de voto, porque a operação resolve conflito com a
  linha existente. FR-008 e SC-004 existem para que isso seja provado, não presumido — e o
  plano precisa verificar esse comportamento contra o Postgres real, não deduzi-lo.
- A dependência escondida é `fechar_rodada_se_devido` ser `security definer`. Nada no
  código avisa que a apuração depende disso; FR-009 transforma essa dependência em teste.
