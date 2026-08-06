# Data Model: Exclusão de conta (009)

Nenhuma tabela nova. A feature muda uma tabela e acrescenta uma função.

## Mudanças em `perfis`

| Mudança | Antes | Depois | Por quê |
|---|---|---|---|
| `anonimizado_em` | não existia | `timestamptz`, nulo | Torna o estado explícito e auditável (FR-006). Nulo significa Perfil ativo. |
| `genero` | `not null`, check `masculino\|feminino` | anulável, mesmo check | Gênero é reidentificador num distrito pequeno; anonimizar exige removê-lo. |
| `idade` | `not null`, check `>= 0` | anulável, mesmo check | Idem. `apelido_obrigatorio_menor` tolera nulo, porque CHECK que resulta em NULL passa no Postgres. |
| FK `perfis_id_fkey` | `references auth.users(id) on delete cascade` | removida | Sem isso a linha anonimizada morre junto com o login. Ver `research.md` § 2. |

## Estados do Perfil

```text
        cadastro                    excluir_minha_conta()
   ( — ) ────────► ATIVO ──────────────────────────────► ANONIMIZADO
                     │                                        │
        anonimizado_em IS NULL                    anonimizado_em IS NOT NULL
        auth.users existe                         auth.users não existe
        nome/genero/idade preenchidos             nome = 'Membro removido',
                                                  demais campos pessoais nulos
```

Transição única e irreversível. Não há caminho de volta: um novo cadastro
gera um Perfil novo, com id novo, sem vínculo com o anterior.

## Classificação dos vínculos

O critério que atravessa a feature inteira: **exige alguém capaz de agir**
(herda), **é intenção sobre o futuro** (some), ou **é registro de algo que
aconteceu** (fica).

| Vínculo | Coluna | Destino | Categoria |
|---|---|---|---|
| Posse de Grupo | `grupos.dono_id` | herdeiro | exige quem aja |
| Rodada aberta | `rodadas_votacao.aberta_por` (`fechada_em is null`) | herdeiro | exige quem aja |
| Voto em Rodada aberta | `votos` (join `rodadas_votacao.fechada_em is null`) | apagado | intenção futura |
| Presença em Ação futura | `confirmacoes_acao` (join `acoes.data_hora > now()`) | apagado | intenção futura |
| Participação em Grupo | `participacoes_grupo.usuario_id` | apagado | vínculo vivo |
| Declaração própria de Líder/Diretor | `liderancas.usuario_id` | apagado | dado pessoal dela |
| Papel de Administrador | `administradores_distrito.usuario_id` | apagado | vínculo vivo |
| Autoria de Ação | `acoes.criador_id` | permanece | histórico |
| Rodada fechada | `rodadas_votacao.aberta_por` (`fechada_em is not null`) | permanece | histórico |
| Voto em Rodada fechada | `votos` | permanece | histórico |
| Presença em Ação passada | `confirmacoes_acao` | permanece | histórico |
| Confirmação de declaração alheia | `liderancas.confirmado_por` | permanece | histórico |
| Promoção de outro Administrador | `administradores_distrito.promovido_por` | permanece | histórico |

## Eleição do herdeiro

```text
SELECT usuario_id
FROM administradores_distrito
WHERE usuario_id <> quem_sai
ORDER BY created_at, usuario_id
LIMIT 1
```

O desempate por `usuario_id` existe para a eleição ser determinística
quando dois Administradores nascem no mesmo instante — caso real no
bootstrap.

**Ausência de herdeiro** recusa a exclusão em dois casos distintos, com
mensagens distintas:

1. quem sai é o único Administrador do distrito — mesmo sem nada a herdar,
   porque um distrito sem Administrador não consegue promover outro
   (`administradores_distrito_checar_regras` exige um pré-existente), e só a
   migration de bootstrap sairia desse estado;
2. quem sai tem Grupo ou Rodada aberta e não existe Administrador nenhum.

## Invariantes preservadas

- **Todo Dono participa do próprio Grupo** — garantida inserindo a
  participação do herdeiro antes do `update` de `dono_id`, porque
  `grupos_dono_vira_participante` só cobre `INSERT`.
- **Fila de espera anda quando vaga é liberada** — garantida por
  `confirmacoes_acao_promover_fila` (`AFTER DELETE`), sem código novo.
- **Dupla Missionária tem composição de gênero válida** — garantida
  indiretamente: Perfil anonimizado nunca permanece em vaga futura, então o
  trigger nunca lê gênero nulo de quem está confirmado.
- **Nome exibido é moderado** — `'Membro removido'` passa em `nome_valido()`.
- **Exibição pública** — `perfil_publico()` devolve
  `coalesce(apelido, nome)`; com apelido nulo, exibe `'Membro removido'` sem
  alteração na função.

## Reflexo no modelo Dart

`Perfil.genero` e `Perfil.idade` passam a ser anuláveis. `menorDeIdade`
retorna `false` para Perfil anonimizado — não há menor a proteger quando não
há mais pessoa por trás do registro.
