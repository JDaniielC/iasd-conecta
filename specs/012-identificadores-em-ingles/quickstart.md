# Quickstart — provar que o rename não mudou nada

**Feature**: 012-identificadores-em-ingles | **Date**: 2026-08-09

Esta feature não adiciona comportamento, então não há o que demonstrar. O que há é o
contrário: **provar que nada mudou**. Tudo abaixo é verificação negativa.

## Pré-requisitos

```bash
cd /Users/jdsc2/projects/iasd
cp .env.example .env      # só se .env ainda não existir
flutter pub get
```

## Linha de base — capturar ANTES de começar

Sem estes números, nenhuma verificação depois significa nada.

```bash
mkdir -p /tmp/012-baseline

# 1. Contagem de testes que passam
flutter test test/unit test/widget 2>&1 | tail -5 > /tmp/012-baseline/tests.txt

# 2. Conjunto de literais de string de lib/ (é o que NÃO pode mudar)
grep -rhoE "'[^']*'|\"[^\"]*\"" --include="*.dart" lib | sort > /tmp/012-baseline/literals.txt
wc -l < /tmp/012-baseline/literals.txt

# 3. Rotas declaradas
grep -oE "path: '[^']*'" lib/app.dart | sort > /tmp/012-baseline/routes.txt

# 4. Estado do banco
git rev-parse HEAD:supabase > /tmp/012-baseline/supabase-tree.txt
```

**Anotar os quatro números/hashes.** São a régua do resto do trabalho.

> Ressalva honesta sobre o item 2: essa extração é uma aproximação — não entende string
> interpolada nem string de múltiplas linhas, e o conjunto muda legitimamente quando um
> arquivo é renomeado e um literal de import muda. Serve como alarme, não como prova
> matemática. A prova de verdade é o método de `research.md` D-001, que nunca edita literal.

## Por etapa (as 5 de `research.md` D-003)

Rodar ao fim de **cada** etapa, antes de commitar.

```bash
flutter analyze                              # 0 issues
flutter test test/unit test/widget           # mesma contagem da linha de base
flutter build web                            # compila
```

E as três verificações negativas:

```bash
# A. Nenhum literal de string mudou
grep -rhoE "'[^']*'|\"[^\"]*\"" --include="*.dart" lib | sort > /tmp/012-atual-literals.txt
diff /tmp/012-baseline/literals.txt /tmp/012-atual-literals.txt

# B. Nenhuma rota mudou
grep -oE "path: '[^']*'" lib/app.dart | sort | diff /tmp/012-baseline/routes.txt -

# C. supabase/ intocado
git diff --name-only HEAD~1 | grep '^supabase/' && echo "PARE: migration foi tocada"
```

**A** e **B** devem sair vazios. Se **A** acusar diferença, ler cada linha: a única diferença
aceitável é um caminho de import que mudou por causa de rename de arquivo ou pasta. **Qualquer
outra diferença é um bug** — provavelmente uma chave de banco ou uma string de UI alterada por
engano, que é exatamente o dano que esta feature pode causar.

**C** deve não imprimir nada.

Ao fim da etapa 3 (`action/`), rodar também:

```bash
dart test test/integration   # exige supabase start; nenhuma asserção pode ter mudado
```

## Ao fim de tudo

| # | Verificação | Critério | Comando/como |
|---|---|---|---|
| 1 | Nenhum identificador em português em `lib/` | SC-001 | Listar tipos e providers e ler um a um: `grep -rhoE "^(class\|enum\|abstract final class\|mixin) [A-Za-z_]+" --include="*.dart" lib \| sort -u` e `grep -rhoE "^final [a-zA-Z]+Provider" --include="*.dart" lib \| sort -u`. **Leitura humana** — nenhum grep decide isto |
| 2 | Nenhum arquivo nem pasta com nome português em `lib/` | SC-002 | `find lib -name "*.dart"` e ler. De 37 arquivos e 4 pastas, para 0 |
| 3 | Contagem de testes idêntica à linha de base | SC-003 | comparar com `/tmp/012-baseline/tests.txt` |
| 4 | Conjunto de literais idêntico, exceto imports | SC-004, SC-005 | diff A acima, com cada diferença justificada |
| 5 | `supabase/` intocado | SC-006 | `git diff --name-only main...HEAD \| grep '^supabase/'` vazio |
| 6 | Rotas idênticas | SC-007 | diff B acima |
| 7 | Mapa completo em `CONTEXT.md` | SC-008 | cada termo do glossário com uma tradução; nenhum identificador servindo a dois termos |
| 8 | Cada etapa compila sozinha | SC-009 | `git log` das 5 etapas; nenhuma depende da seguinte |

## Verificação manual — o app

Rodar e clicar. Nenhum teste automatizado prova que a UI não mudou de texto.

```bash
flutter run -d chrome
```

| # | Tela | Esperado |
|---|---|---|
| 1 | Lista de Grupos | Mesmos textos, mesmos filtros, mesma ordenação |
| 2 | Lista de Ações | Mesmos períodos (Sábado / Hoje / Essa semana / Outras datas), mesmo filtro "Só Sábado" |
| 3 | Detalhe de Ação | Confirmar presença funciona; fila de espera promove ao desistir |
| 4 | Rodada de votação | Votar, trocar voto, apurar |
| 5 | Cadastro de Perfil | Mesmos campos, mesmas mensagens de erro, mesma exigência de Apelido para menor |
| 6 | Política de Privacidade e Termos | Texto **idêntico**, palavra por palavra |
| 7 | Rotas salvas | Um link `/grupos/<id>` antigo continua abrindo o mesmo Grupo |

## Definição de pronto

- [ ] Linha de base capturada **antes** da primeira etapa, com os quatro valores anotados
- [ ] `CONTEXT.md` com o mapa completo, commitado **antes** de qualquer rename
- [ ] As 5 etapas commitadas separadamente, cada uma compilando e com gates passando
- [ ] Etapa `action/` só iniciada depois da feature 011 mergeada
- [ ] As 8 verificações finais conferidas, com números reais
- [ ] Verificação manual, itens 1 a 7
- [ ] Nenhum arquivo em `supabase/` no diff total da feature
