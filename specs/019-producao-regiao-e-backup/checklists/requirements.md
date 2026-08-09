# Specification Quality Checklist: Produção — confirmar região e resolver backup

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

- [x] Princípio I — nenhum termo novo; nenhuma linha de código do app
- [x] Princípio II — nenhum dado novo, mas trata de **onde** o dado existente mora e para onde é copiado. Backup é cópia integral, inclusive de quem pediu exclusão (FR-009)
- [x] Princípio IV — nenhuma regra de domínio tocada
- [x] Princípio V — nenhum papel novo

## Notes

- **Duas afirmações não verificadas sobre um ambiente que já existe.** `.env.prod` aponta para
  projeto Supabase real e `deploy-web.yml:34-42` já injeta segredos de produção, mas
  `legal_metadata.dart:24-26` ainda diz *"ainda não provisionada"*.
- **FR-004 tem precedência declarada**: se a região não for brasileira, corrigir a Política vem
  **antes** de qualquer plano de migração. Afirmação falsa a titular é o dano imediato;
  migração é o conserto.
- **Parte desta feature não pode ser feita por quem só tem o repositório** — exige acesso ao
  painel do fornecedor. Está dito, em vez de fingir que dá para automatizar.
- A decisão de backup é do responsável pelo app, não técnica. A spec garante que a escolha seja
  **feita e registrada**, não que seja uma específica.
