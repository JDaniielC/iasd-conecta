# Specification Quality Checklist: Novidades — o que mudou no app

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-08-10
**Feature**: [spec.md](../spec.md)

## Content Quality

- [X] No implementation details (languages, frameworks, APIs)
- [X] Focused on user value and business needs
- [X] Written for non-technical stakeholders
- [X] All mandatory sections completed

Nota sobre o primeiro item: o Contexto cita `PENDENCIAS.md` e
`public.versoes_texto_legal` como os lugares onde o registro existe hoje. É diagnóstico do
estado atual — a evidência de que o problema existe —, não prescrição de solução. Nenhum
requisito nomeia mecanismo: FR-013 diz "no aparelho" porque **onde** o estado mora é a
decisão de privacidade que a feature toma, não um detalhe técnico.

## Requirement Completeness

- [X] No [NEEDS CLARIFICATION] markers remain
- [X] Requirements are testable and unambiguous
- [X] Success criteria are measurable
- [X] Success criteria are technology-agnostic (no implementation details)
- [X] All acceptance scenarios are defined
- [X] Edge cases are identified
- [X] Scope is clearly bounded
- [X] Dependencies and assumptions identified

Nota sobre os marcadores: a ambiguidade da data **não** virou
`[NEEDS CLARIFICATION]`. Ela tem leitura defensável (dia/mês/ano, padrão brasileiro), está
registrada como a primeira Assumption com a consequência concreta escrita — a lista nasce
vazia —, e a spec diz qual linha muda se a intenção for outra. Marcar teria bloqueado o
planejamento por algo que `/speckit-clarify` resolve numa resposta.

## Feature Readiness

- [X] All functional requirements have clear acceptance criteria
- [X] User scenarios cover primary flows
- [X] Feature meets measurable outcomes defined in Success Criteria
- [X] No implementation details leak into specification

## Cobertura FR → SC

| FR | Coberto por |
|---|---|
| FR-001 lista do mais recente ao mais antigo | SC-001 |
| FR-002 data e texto para quem usa | SC-001 |
| FR-003 sem jargão técnico | SC-002 |
| FR-004 alcançável a partir da Home | SC-006 |
| FR-005 Visitante vê o mesmo | SC-001 |
| FR-006 marco de 6/10/2026 | SC-002 (nada anterior listado) |
| FR-007 lista vazia se explica | SC-006 |
| FR-008 indicação de novidade | SC-004 |
| FR-009 abrir faz sumir | SC-004 |
| FR-010 não volta sem novidade nova | SC-004 |
| FR-011 primeira instalação sem aviso | SC-005 |
| FR-012 nada no servidor sobre leitura | SC-003 |
| FR-013 estado no aparelho | SC-003 |
| FR-014 nenhuma frase nova na Política | SC-007 |
| FR-015 escritas à mão | SC-002 |
| FR-016 remoção também é descrita | SC-001 |
| FR-017 critério escrito no repositório | SC-002 |

17/17 requisitos com critério de sucesso associado.

## Notes

- **A armadilha desta feature é o texto, não o código.** A tela é simples; o risco é a lista
  degenerar em changelog técnico com o tempo, escrita por quem tem o commit fresco na cabeça
  em vez de por quem pensa no distrito. FR-003, FR-015 e FR-017 existem por isso, e SC-001
  manda **três pessoas do distrito** lerem — não é opinião de quem escreveu.
- **A segunda armadilha é gravar "já vi" no servidor**, que é o jeito óbvio e errado. US3 é
  P2 junto com US2 justamente para que a decisão de privacidade seja tomada junto com o
  aviso, e não depois que ele já existir.
- A data futura significa que **a tela nasce vazia**. Vale conferir com o dono do app antes
  do plano se é isso mesmo, ou se ele quer os 21 itens retroativos.
