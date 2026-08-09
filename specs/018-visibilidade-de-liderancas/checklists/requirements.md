# Specification Quality Checklist: Visibilidade das declarações de Líder/Diretor

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

- [x] Princípio I — nenhum termo novo; usa Líder/Diretor, Ministério, Administrador do distrito
- [x] Princípio II — a feature **só reduz** exposição. É a razão de ela existir
- [x] Princípio IV — nenhuma regra de borda
- [x] Princípio V — nenhum papel novo

## Notes

- **A tela esconde, o banco não.** `liderancas_select_public ... using (true)`
  (`20260724100000_leadership.sql:73-76`) deixa qualquer Visitante ler declaração **pendente** e
  **rejeitada** pela API. A UI só renderiza confirmadas — e esconder não é proteger.
- **O glossário é explícito sobre o limite**: `CONTEXT.md` promete pública a *"identificação do
  Líder"*, não a lista de quem tentou e não conseguiu.
- **Passou pela auditoria de segurança porque a tela esconde.** `SECURITY-AUDIT.md` está limpo,
  com os três achados anteriores corrigidos. Este é justamente o tipo que escapa de auditoria
  que olha tela.
- SC-001 exige verificação **por consulta direta à API**, não por inspeção de tela — senão o
  teste reproduz o mesmo erro que criou o problema.
