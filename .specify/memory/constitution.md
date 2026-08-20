<!--
Sync Impact Report
Version change: 1.1.0 → 1.2.0
Modified principles: IV. Integridade das Regras de Domínio Testada — de
  "teste automatizado antes de ser considerada pronta" (teste antes de fechar)
  para **teste-primeiro**: o teste do comportamento novo ou alterado DEVE
  existir e DEVE falhar antes do código de produção, e o vermelho DEVE ser pelo
  motivo do requisito. Acrescenta as quatro exceções declaradas e o piso de
  cobertura medido por comando versionado. Nenhuma remoção nem redefinição
  incompatível — a lista de regras de domínio enumeradas continua idêntica —
  daí MINOR, não MAJOR.
Added sections: none (subseções dentro do Princípio IV existente)
Removed sections: none
Templates requiring updates:
  ⚠️ .specify/templates/tasks-template.md — EDITADO. Dizia "Tests are OPTIONAL -
     only include them if explicitly requested in the feature specification",
     em contradição direta com um princípio NON-NEGOTIABLE. Seis trechos
     corrigidos: o cabeçalho **Tests**, os três títulos "Tests for User Story N
     (OPTIONAL - only if tests requested)", "Additional unit tests (if
     requested)", e "Tests (if included) MUST be written and FAIL before
     implementation" — este último ganhou a exigência do vermelho pelo motivo
     certo. A nota "Write these tests FIRST, ensure they FAIL before
     implementation" já existia e ficou como estava.
  ✅ .specify/templates/plan-template.md — o Constitution Check é genérico
     ("[Gates determined based on constitution file]"), lê o arquivo em tempo de
     execução; nenhuma edição necessária
  ✅ .specify/templates/spec-template.md — fala de "Independent Test" como
     critério de aceite da user story, não de quando o teste é escrito; nenhuma
     edição necessária
Follow-up TODOs:
  - TODO(RATIFICATION_DATE): data de adoção original ainda desconhecida.
  - Código Dart das features 001-004 permanece com identificadores em
    português; tradução é gradual, ao tocar cada arquivo (ver Princípio I).
  - `test/integration` continua fora da medição de cobertura (exigiria o ciclo
    de vida do Supabase local dentro do gate rápido). Registrado em
    PENDENCIAS.md.
-->

# Rede IASD Vitória de Santo Antão Constitution

## Core Principles

### I. Linguagem Ubíqua do Domínio (NON-NEGOTIABLE)

O glossário em `CONTEXT.md` é a fonte de verdade dos termos do domínio (Visitante,
Usuário, Apelido, Categoria de Grupo, Ação sugerida, Grupo, Participar do Grupo,
Dono do Grupo, Ação, Ação candidata, Rodada de votação, Votar, Igreja,
Administrador do distrito, Ministério, Líder/Diretor, Dupla Missionária). Specs,
schema do banco (tabelas/colunas/funções/triggers) e mensagens de UI DEVEM usar
esses termos exatos, em português, e DEVEM evitar os sinônimos listados em cada
entrada "_Avoid_". Um termo novo ou renomeado só entra em código depois de
atualizado em `CONTEXT.md`.

**Fronteira de idioma (código Dart)**: identificadores em Dart (classes,
variáveis, métodos, nomes de arquivo) DEVEM ser escritos em inglês, usando uma
tradução consistente do termo do glossário (ex.: Grupo→Group, Ação→Action,
Perfil→Profile, Rodada de votação→VotingRound) — a mesma tradução em todo o
código, nunca duas traduções diferentes pro mesmo conceito. O banco de dados
(tabelas/colunas/funções/triggers) e toda string visível ao usuário continuam em
português, sem exceção. Código Dart já existente escrito em português não
precisa de um passe de tradução dedicado; ao tocar um arquivo por outro motivo,
traduza os identificadores daquele arquivo pro inglês como parte da mudança.

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

Toda regra de negócio central tem teste automatizado, incluindo no mínimo:
promoção automática da fila de espera quando uma vaga é liberada; desempate por
sorteio aleatório ao fechar uma Rodada de votação; revogabilidade de voto (só a
última escolha conta) e de Participar (Grupo ou Ação); descarte de candidatas
perdedoras e suas presenças ao fechar a Rodada; validação de composição de
gênero de Dupla Missionária. Regressão nessas regras bloqueia merge.

**Teste-primeiro**: o teste que descreve um comportamento novo ou alterado DEVE
existir e DEVE falhar antes do código de produção que o satisfaz. O teste NÃO
DEVE ser escrito depois, a partir do código pronto — um teste escrito olhando
para a implementação descreve o que o código faz, não o que o requisito pede, e
as duas coisas divergirem em silêncio é exatamente o defeito que o teste existia
para pegar. Correção de defeito segue a mesma regra: primeiro o teste que
reproduz o defeito e falha, depois o conserto.

**O vermelho DEVE ser pelo motivo do requisito.** Falhar porque não compila,
porque o widget não foi encontrado na árvore ou porque o setup não montou é
vermelho que não prova nada — e vira verde assim que o obstáculo sai, com o
requisito ainda por implementar. Quem escreve o teste confere a mensagem da
falha antes de escrever o código de produção.

**Exceções declaradas, e são só estas**: correção de texto de tela sem mudança
de regra, tradução de identificador (Princípio I), movimentação de código sem
alteração de comportamento observável, e cobertura retroativa de código que já
existe — que não é comportamento novo nem alterado, e por isso nasce verde.

**Piso de cobertura**: a cobertura de linha dos testes de unidade e de widget é
medida por um comando único, versionado no repositório, que reprova quando o
número cai abaixo do piso registrado. O piso sobe quando a cobertura sobe; NÃO
DEVE ser baixado para fazer uma árvore vermelha passar. O que fica fora do
denominador DEVE carregar, escrito junto da exclusão, o motivo e onde aquele
código é provado.

**Rationale**: são as regras com mais casos de borda e maior custo de erro
silencioso (ex.: vaga que não libera, voto que conta errado, dupla inválida
liberada). Cobertura textual na spec não substitui verificação executável.

O teste-primeiro existe porque a redação anterior — "teste antes de ser
considerada pronta" — permitia exatamente o que a primeira medição de cobertura
deste projeto encontrou em 2026-08-20: a regra tinha teste em algum lugar da
suíte de integração, e a tela que a pessoa usa não tinha nenhum. Dez páginas
somavam 476 linhas com 7 cobertas, e quatro delas eram Rodada de votação e
Declaração de liderança — as regras enumeradas acima como inegociáveis.

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

**Version**: 1.2.0 | **Ratified**: TODO(RATIFICATION_DATE): confirmar data original de adoção | **Last Amended**: 2026-08-20
