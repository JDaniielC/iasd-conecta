# Specification Quality Checklist: Consentimento de responsável para menor de idade

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

- [x] Princípio I — termo novo (**Responsável**) exige entrada em `CONTEXT.md` antes do código (FR-013)
- [x] Princípio II — declaração completa. A feature **acrescenta** dado pessoal de terceiro (nome e contato de quem não é usuário), e isso está dito com todas as letras em vez de minimizado
- [x] Princípio IV — nenhuma regra de borda tocada
- [x] Princípio V — Responsável **não é papel do sistema**: sem login, sem permissão, sem tela. São campos no cadastro de um menor

## Notes

- **Esta é a única feature do lote em que o app já afirma por escrito algo que o código não faz.**
  `privacy_policy_page.dart:233-236` diz a um pai que é ele quem aceita a política pela criança;
  `grep -rniE "responsav|parental|guardian" lib supabase/` retorna zero. Público confirmado a
  partir de 6 anos (`CATEGORIAS-DE-ACAO.md:13-14`).
- **Um [NEEDS CLARIFICATION] foi deliberadamente convertido em assumption**: o limiar exato de
  idade. A Política diz "até 12 anos" e `REVISAO-JURIDICA.md:93` propõe "menor que 12" — são
  coisas diferentes na borda. É a decisão que mais muda comportamento, e está marcada para
  `/speckit-clarify`.
- **Pendência declarada, não escondida**: cadastros de menor que já existem sem autorização. A
  feature não os corrige nem os bloqueia, e diz isso.
