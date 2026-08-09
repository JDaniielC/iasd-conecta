# Specification Quality Checklist: Deploy do app web em Cloud Storage com CDN

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

- [x] Princípio I — nenhum termo novo. Conta de serviço é credencial de máquina, não papel de domínio, e não entra em `CONTEXT.md`
- [x] Princípio II — nenhum dado pessoal. O que se publica é o app compilado; as duas chaves injetadas já são públicas por natureza
- [x] Princípio IV — nenhuma linha do app muda
- [x] Princípio V — nenhum papel novo

## Notes

- **US2 é P1 junto com a US1, não depois.** Publicar sem invalidar o cache é pior do que não
  publicar: cria a convicção de que a correção foi ao ar quando ela não chegou a ninguém que já
  usou o app. O ticket registra TTL padrão de 3600s.
- **Contradição resolvida antes de escrever**: o ticket fala em "sair do EC2" e o `.env.prod`
  aponta para Supabase Cloud. Confirmado com o responsável em 2026-08-09 — são camadas
  diferentes: front no GCS+CDN, banco no Supabase. A camada de banco é a feature 019.
- **Nomes de recurso não são repetidos aqui**, de propósito: estão em
  `.tickets/IASD-CI-GCS-UPLOAD.md:9-13`, e duplicá-los criaria duas verdades.
- Três lacunas conhecidas e declaradas: sem rollback de um comando, sem homologação, e sem
  verificação de disponibilidade depois de publicar.
