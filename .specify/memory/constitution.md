<!--
Sync Impact Report
Version change: [TEMPLATE] → 1.0.0 (initial ratification)
Modified principles: n/a (first fill of template placeholders)
Added sections: all 5 Core Principles, Requisitos de Domínio e Compliance,
  Fluxo de Desenvolvimento, Governance
Removed sections: none
Templates requiring updates:
  ✅ .specify/templates/plan-template.md — Constitution Check gate is generic
     ("[Gates determined based on constitution file]"), no edit needed
  ✅ .specify/templates/spec-template.md — no constitution-specific references found
  ✅ .specify/templates/tasks-template.md — no constitution-specific references found
  ✅ .claude/skills/speckit-*/SKILL.md — no CLAUDE-only or stale agent references found
Follow-up TODOs:
  - TODO(RATIFICATION_DATE): original adoption date unknown; using constitution
    creation date as placeholder until confirmed by project owner.
-->

# Rede IASD Vitória de Santo Antão Constitution

## Core Principles

### I. Linguagem Ubíqua do Domínio (NON-NEGOTIABLE)

O glossário em `CONTEXT.md` é a fonte de verdade dos termos do domínio (Visitante,
Usuário, Apelido, Categoria de Grupo, Ação sugerida, Grupo, Participar do Grupo,
Dono do Grupo, Ação, Ação candidata, Rodada de votação, Votar, Igreja,
Administrador do distrito, Ministério, Líder/Diretor, Dupla Missionária). Specs,
código, nomes de tabelas/colunas, endpoints e mensagens de UI DEVEM usar esses
termos exatos e DEVEM evitar os sinônimos listados em cada entrada "_Avoid_". Um
termo novo ou renomeado só entra em código depois de atualizado em `CONTEXT.md`.

**Rationale**: o domínio tem distinções sutis e fáceis de confundir (Ação vs.
Grupo, Dono do Grupo vs. Líder/Diretor, Participar do Grupo vs. Participar de uma
Ação). Vocabulário divergente entre spec, código e usuário final reintroduz essas
confusões e quebra rastreabilidade entre requisito e implementação.

### II. Privacidade e LGPD por Padrão (NON-NEGOTIABLE)

Nenhum dado pessoal é coletado, exibido ou retido além do que o glossário
autoriza explicitamente. Em particular: idade nunca é exibida a outros usuários;
menor de idade é exibido por Apelido, nunca pelo nome real; nome é moderado
contra palavrões antes de exibição; consentimento LGPD é obrigatório e registrado
no cadastro; campos opcionais (telefone, Igreja de origem) permanecem opcionais
em toda a stack, sem exigência disfarçada. Qualquer novo campo pessoal exige
consentimento e finalidade explícitos antes de ser implementado.

**Rationale**: o produto atende uma comunidade real, incluindo menores de idade,
sob a legislação brasileira (LGPD). Vazamento de idade, exposição de nome real de
menor, ou coleta sem consentimento são danos concretos a pessoas reais, não
riscos abstratos.

### III. Desenvolvimento Guiado por Spec

Nenhuma feature é implementada sem passar pelo fluxo do Spec Kit
(`/speckit-specify` → `/speckit-clarify` → `/speckit-plan` → `/speckit-tasks` →
`/speckit-implement`). Specs e plans são escritos em português, usando os termos
do Princípio I. Ambiguidade de regra de negócio é resolvida via
`/speckit-clarify` antes do plano, não decidida ad-hoc durante a implementação.

**Rationale**: o domínio tem regras de negócio intrincadas (fila de espera,
rodadas de votação paralelas, revogabilidade de voto, composição de Dupla
Missionária). Pular a etapa de spec/clarify desloca essas decisões para o código,
onde ficam implícitas e não revisáveis.

### IV. Integridade das Regras de Domínio Testada (NON-NEGOTIABLE)

Toda regra de negócio central tem teste automatizado antes de ser considerada
pronta, incluindo no mínimo: promoção automática da fila de espera quando uma
vaga é liberada; desempate por sorteio aleatório ao fechar uma Rodada de votação;
revogabilidade de voto (só a última escolha conta) e de Participar (Grupo ou
Ação); descarte de candidatas perdedoras e suas presenças ao fechar a Rodada;
validação de composição de gênero de Dupla Missionária. Regressão nessas regras
bloqueia merge.

**Rationale**: são as regras com mais casos de borda e maior custo de erro
silencioso (ex.: vaga que não libera, voto que conta errado, dupla inválida
liberada). Cobertura textual na spec não substitui verificação executável.

### V. Simplicidade e Papéis Mínimos

Os papéis do sistema são exatamente os definidos no glossário: Visitante,
Usuário, Dono do Grupo, Líder/Diretor, Administrador do distrito. Nenhuma
feature introduz papel, permissão ou hierarquia adicional sem primeiro atualizar
`CONTEXT.md` e justificar por que os papéis existentes são insuficientes.
Soluções preferem o caminho mais simples que atende a regra descrita — sem
generalização especulativa para necessidades futuras não especificadas.

**Rationale**: é um app de comunidade voluntária, não uma plataforma
multi-tenant corporativa. Complexidade de permissões não pedida pelo domínio
aumenta custo de manutenção sem benefício correspondente.

## Requisitos de Domínio e Compliance

Toda spec que toque dado pessoal (nome, Apelido, idade, gênero, telefone, Igreja
de origem) DEVE declarar explicitamente: qual dado é coletado, sua finalidade,
quem pode vê-lo, e se exige consentimento adicional além do consentimento LGPD
de cadastro. Toda spec que toque Ação, Grupo ou Rodada de votação DEVE declarar
o comportamento de borda relevante do Princípio IV (fila de espera, empate,
revogação, descarte) mesmo quando não for o foco principal da feature.

## Fluxo de Desenvolvimento

O ciclo padrão é: `/speckit-specify` gera a spec em português usando o glossário;
`/speckit-clarify` resolve ambiguidade de regra de negócio antes do plano;
`/speckit-plan` produz o Constitution Check contra os cinco princípios acima;
`/speckit-tasks` quebra em tarefas, marcando explicitamente as que cobrem regras
do Princípio IV; `/speckit-implement` executa. Divergência entre o que a spec
promete e o que o código faz (ex.: mensagem de UI dizendo "revogável" enquanto o
código não permite desfazer) é tratada como violação de constituição, não como
detalhe de implementação.

## Governance

Esta constituição prevalece sobre qualquer prática, template ou preferência de
implementação em conflito. Emendas exigem: (1) proposta com o texto exato da
mudança, (2) atualização do Sync Impact Report no topo deste arquivo, (3)
verificação de que `plan-template.md`, `spec-template.md` e `tasks-template.md`
continuam consistentes com os princípios revisados. Versionamento segue semver:
MAJOR para remoção/redefinição incompatível de princípio, MINOR para princípio
novo ou expansão material de um existente, PATCH para redação/clareza sem mudar
regra. Todo `/speckit-plan` DEVE incluir o Constitution Check preenchido contra
os cinco princípios; violação não justificada em Complexity Tracking bloqueia a
fase seguinte.

**Version**: 1.0.0 | **Ratified**: TODO(RATIFICATION_DATE): confirmar data original de adoção | **Last Amended**: 2026-07-23
