## Why

`test/integration/consentimentos_por_versao_test.dart`, caso *"(d) Perfil
anonimizado sai da contagem"*, falha de forma intermitente quando a suíte roda
inteira: **2 falhas em ~8 execuções** em 2026-08-11. Rodado sozinho, o arquivo
passa sempre.

A falha medida é `Expected: <1> Actual: <0>`, e é na contagem de **baldes**, não
de pessoas: `consentimentos_por_versao()` devolve **nenhuma linha** para a versão
isolada `9.9-anon`, quando o teste espera uma.

Teste que falha 1 em 4 sem motivo conhecido é pior que teste ausente: ele ensina
a suíte inteira a ser ignorada. E há uma consequência concreta e próxima — a
change `travar-deploy-com-teste-vermelho` liga a publicação ao resultado da
suíte. Ligar o deploy a uma suíte instável transforma higiene em transtorno.

`PENDENCIAS.md` § 2.6.

## What Changes

A causa é encontrada e removida, e a suíte volta a ser determinística com os
arquivos rodando em paralelo.

## Capabilities

### New Capabilities
- `suite-de-integracao`: as garantias que a suíte de integração dá sobre si
  mesma — isolamento entre arquivos e determinismo.

## Impact

- `test/integration/` — o arquivo culpado, que ainda não se sabe qual é.
- Possivelmente `test/integration/db_test_helper.dart`, se a causa for
  compartilhada.
- Nenhuma mudança em `lib/` nem em migration é esperada. Se for preciso mudar
  código de produção para o teste passar, a causa era outra e a change muda de
  escopo.
