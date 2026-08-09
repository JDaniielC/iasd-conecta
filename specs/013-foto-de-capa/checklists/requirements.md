# Specification Quality Checklist: Foto de capa de Grupo e de Ação

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

- [x] Princípio I — termos do glossário usados exatos (Grupo, Ação, Visitante, Usuário,
      Perfil, Dono do Grupo, Administrador do distrito, Rodada de votação, Ação candidata).
      Dois termos **novos** (Foto de capa, Denúncia de imagem) exigem entrada em `CONTEXT.md`
      antes do código — virou FR-029
- [x] Princípio II — declaração completa: dado, finalidade, quem vê, consentimento. Mais
      FR-027, FR-028 e FR-030, que colocam Política de Privacidade e `MAPA-DE-DADOS.md`
      dentro da entrega
- [x] Princípio IV — declarado: nenhuma regra de borda muda; única interação é a candidata
      descartada levar a capa junto (FR-022)
- [x] Princípio V — nenhum papel novo; detalha o escopo de moderação que `CONTEXT.md` deixou
      em aberto

## Notes

- **Correção de leitura do pedido, registrada no topo da spec**: o texto original diz "deve
  ser aconselhado ser enviado foto pessoais ou de menores". Faltou um "não". A spec adota
  "aconselhado a NÃO enviar", pela segunda metade da frase ("incentivando sobre imagens
  ilustrativas"). Se a leitura estiver errada, a spec inteira está errada — é a primeira coisa
  a confirmar.

- Validado em 1 iteração. Três decisões resolvidas com o usuário antes da escrita, nenhum
  `[NEEDS CLARIFICATION]` chegou ao arquivo:
  1. **Aviso + remoção pelo Administrador + denúncia** (em vez de só aviso, ou de aprovação
     prévia).
  2. **Imagem some com o dono**: Grupo apagado e Ação cancelada levam a capa; Ação encerrada
     mantém; na exclusão de conta, capa de Grupo herdado fica e capa de Ação avulsa some.
  3. **Uma capa por Grupo/Ação**, controlada por quem administra.

- **Esta feature quebra uma afirmação que hoje é verificada**: `MAPA-DE-DADOS.md:22` declara,
  com grep como prova, que foto/avatar **não é coletado**. Por isso a atualização dos
  documentos virou requisito funcional (FR-027, FR-028, FR-030) e critério de sucesso
  (SC-007), e não item de polimento. Entregar o upload sem os documentos deixaria a Política
  de Privacidade descrevendo um app que não existe mais.

- **A assumption mais importante é negativa**: o app **não** analisa a imagem. Não detecta
  rosto, idade nem conteúdo impróprio. Toda a proteção é humana — aviso antes, denúncia
  depois, remoção pelo Administrador do distrito. A spec diz isso explicitamente porque a
  tentação de assumir moderação automática, num app que hospeda imagem pública, é o caminho
  mais curto para uma promessa que o código não cumpre.

- **Risco residual declarado, não resolvido**: entre a publicação de uma imagem imprópria e a
  denúncia, ela fica pública para qualquer pessoa, inclusive Visitante. As três opções de
  proteção foram apresentadas e a escolhida publica na hora. Aprovação prévia eliminaria essa
  janela ao custo de uma fila de moderação para uma pessoa só.
