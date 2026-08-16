# Instruções do repositório

## Fluxo de trabalho por change (OpenSpec)

Cada change do OpenSpec vira uma branch própria. Isso existe para a verificação
ficar focada: dá para olhar o diff de um ticket sem o ruído dos outros.

```
/opsx:apply <change>   →  git checkout -b change/<nome-da-change>
                          commits normais na branch
/opsx:archive <change> →  git checkout main
                          git merge --squash change/<nome-da-change>
                          git commit
                          git branch -D change/<nome-da-change>
```

`-D` e não `-d`: o squash não registra ancestralidade, então o `-d` recusa
dizendo que a branch "não está totalmente mesclada". Conferir antes com
`git diff change/<nome> main --stat` — vazio quer dizer que `main` já tem tudo.

- **Uma branch por change**, nomeada `change/<nome-da-change>`.
- **Squash no merge**: a change inteira vira um commit em `main`. O histórico
  detalhado fica na branch até ela ser apagada; o que permanece é o `tasks.md`
  arquivado, que é o registro que se lê depois.
- **Apagar a branch** logo após o merge.
- Trabalho que não é de change (correção pontual, ledger avulso) continua
  direto em `main`.

## Testes de integração

`dart test test/integration` roda os arquivos **em paralelo contra o mesmo
Postgres**. A capability `suite-de-integracao` exige determinismo, e o modo de
quebrar é sempre o mesmo: um arquivo alcança linha ou contagem de outro.

Estado global conhecido: `administradores_distrito`. `excluir_minha_conta`
decide pela contagem de administradores, então dois arquivos com Administrador
vivo ao mesmo tempo se atropelam. `createTestDistrictAdmin` toma um lock
consultivo de sessão por isso — não remover sem ler o comentário lá.

Ao escrever teste novo: escopar tudo por UUID próprio, e nunca apagar por
padrão que outro arquivo possa casar.


## Idioma do código

**A regra não mora aqui — mora em [CONTEXT.md](./CONTEXT.md), seção "Fronteira
de idioma", com o glossário termo a termo.** Identificador Dart em inglês;
banco, chave de mapa, string de tela e comentário em português.

Este arquivo só acrescenta o *quando*: **conferir os identificadores ao fechar
uma tarefa**, não ao abrir a próxima. A regra falha em silêncio — código em
português roda igual, passa no `flutter analyze` e passa nos testes. O único
momento em que alguém olha é se olhar de propósito.

Duas armadilhas já vistas nesta base:

- **Traduzir por conta própria em vez de consultar o glossário.** `Local` é
  `location`, não `place`; `Participante` é `member`, não `participant`. Uma
  tradução por conceito é a regra, e duas traduções para a mesma coisa é pior
  do que o português.
- **Achar que a regra é nova.** Ela é da constituição, Princípio I, e vale para
  código de teste tanto quanto para código de produção — só o *nome do arquivo*
  de teste é exceção declarada.

## Commit por sessão de trabalho

A branch por change existe para **dividir responsabilidade**, e uma branch com
um commit gigante no fim não divide nada — ninguém revisa 40 arquivos de uma
vez, e `git bisect` não tem onde pisar.

**Feche um commit sempre que uma frente de trabalho ficar verificada**, mesmo
com a change longe do fim. Uma frente é um conjunto que se sustenta sozinho:
"o banco e a prova dele", "a tradução de identificadores", "o texto legal e a
versão dele". Se o commit precisa de "e também" para ser descrito, são dois.

Regras que fazem isso funcionar:

- **Só commita o que passou no gate.** Rodar o gate depois do commit é
  descobrir o defeito com ele já no histórico. Os números reais vão no corpo
  da mensagem — `flutter analyze` 0 issues, contagem de teste, não "os testes
  passaram".
- **`git add` por caminho, nunca `git add -A`.** Numa sessão com agentes em
  paralelo, `-A` varre arquivo que outro agente está no meio de editar e
  congela um rename pela metade.
- **Não commita trabalho de agente que ainda está rodando.** Espere o relatório
  e o gate.
- O squash para `main` continua valendo. O histórico detalhado morre com a
  branch — o que ele serve é a revisão enquanto a branch vive, e é para isso
  que ele precisa ser legível.

## Recusa de RLS é ausência, não erro

**Todo `update` ou `delete` que o cliente manda ao Supabase confere quantas
linhas afetou.** No Postgres, uma policy que recusa não levanta exceção — ela
faz a linha não existir para aquela sessão, e o `update` afeta zero linhas e
volta com sucesso. Um método que não olha o resultado reporta que deu certo
sobre nada.

```dart
final affected = await _client.from(t).update({...}).eq('id', id).select();
if (affected.isEmpty) {
  throw StateError('...');   // a mensagem que a tela vai mostrar
}
```

Isto custou três achados na change `chat-de-grupo-e-acao`, sempre o mesmo
sintoma com causas diferentes:

1. `pode_ver_chat_acao` sem o braço de Administrador — a remoção não alcançava
   a linha, e a tela do moderador dizia que a mensagem tinha saído enquanto ela
   continuava visível para todo mundo.
2. `ChatRepository.removeMessage` sem `.select()` — mesmo sintoma, causa nova.
3. `ChatRepository.resolveReport` sem `.select()` — a denúncia voltava
   `pendente` sem explicação.

**Em teste de integração, a asserção correspondente é `affectedRows`, não
`expect(..., throwsA(...))`.** Um teste que espera exceção numa recusa de RLS
passa pelo motivo errado, ou não passa nunca. Ver `chat_moderacao_test.dart`,
que conta linhas afetadas de propósito.

A regra vale para escrita do cliente. Dentro de função `security definer` o
raciocínio muda — lá a RLS não se aplica, e o que precisa de checagem explícita
é a autoridade de quem chamou.
