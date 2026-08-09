# Specification Quality Checklist: Meu Perfil — ver e corrigir os próprios dados

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

- [x] Princípio I — nenhum termo novo; usa Perfil, Apelido, Igreja de origem
- [x] Princípio II — nenhum dado novo. Dá ao titular acesso e correção do que já é dele (LGPD art. 18, II e III). Exposição não aumenta
- [x] Princípio IV — nenhuma regra de borda. O nome sempre veio do Perfil, sem cópia a divergir
- [x] Princípio V — nenhum papel novo

## Notes

- **A permissão de escrita já existe e nunca foi usada**: `perfis_update_own`
  (`20260723191202_perfis_igrejas.sql:76-79`). A feature é cliente puro — o que explica por que a
  lacuna durou tanto sem ninguém medir o custo.
- Diferente da 015, aqui **a Política é honesta**: ela diz que a tela não existe
  (`privacy_policy_page.dart:173-179`). Não é promessa quebrada, é lacuna assumida.
- **Idade e gênero ficam fora da edição**, por decisão registrada: gênero valida composição de
  Dupla Missionária e idade decide a exigência de Apelido. Editá-los carrega regra de domínio
  que esta feature não quer.
