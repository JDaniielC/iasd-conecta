# Quickstart: Rodada de Votação

## Pré-requisitos

Mesmos das features anteriores — `supabase start` com a migration desta
feature aplicada (`supabase db reset`).

## Roteiro de validação (mapeado às Acceptance Scenarios da spec)

1. **Abrir Rodada e propor candidata** (US1): participante de um Grupo abre
   Rodada com prazo futuro, propõe duas candidatas → ambas listadas.
2. **Não-participante recusado** (US1, cenário 4): quem não participa do
   Grupo não abre Rodada nem propõe candidata.
3. **Votar e trocar de voto** (US2): votar numa candidata, trocar pra
   outra → só a última conta.
4. **Fechar por prazo vencido** (US3, cenário 1): Rodada com prazo no
   passado, qualquer interação (ex.: buscar detalhes) fecha e apura antes
   de prosseguir.
5. **Dono encerra antes do prazo** (US3, cenário 2): Dono do Grupo força o
   fechamento.
6. **Vencedora vira Ação confirmada** (US3, cenário 3): candidata líder
   vira `confirmada = true`, demais somem.
7. **Empate resolvido por sorteio** (US3, cenário 4): duas candidatas com
   votos iguais → uma escolhida aleatoriamente.
8. **Sem candidata, sem vencedora** (US3, cenário 5): Rodada sem nenhuma
   candidata fecha sem `vencedora_id`.
9. **Confirmar presença numa candidata** (US4): funciona igual Ação
   avulsa, com ou sem voto.
10. **Cancelar Ação de Grupo** (US5): quem propôs a vencedora, ou o Dono do
    Grupo, cancela; demais participantes não conseguem.

## Verificações estruturais (via SQL, banco local)

```sql
-- FR-008: fechamento preguicoso (prazo ja vencido)
select public.fechar_rodada_se_devido('<rodada-com-prazo-passado>');
select fechada_em, vencedora_id from public.rodadas_votacao where id = '<rodada>';

-- FR-009/FR-010: so o Dono forca fechamento antes do prazo
select public.fechar_rodada_se_devido('<rodada-aberta>', true);
-- como nao-dono deve levantar excecao "só o Dono do Grupo encerra..."

-- FR-013/FR-014: vencedora confirmada, perdedoras somem
select confirmada from public.acoes where id = '<candidata-vencedora>';
select count(*) from public.acoes where rodada_id = '<rodada>' and confirmada = false;
-- deve ser 0 apos fechar

-- FR-018: sem candidata, sem vencedora
select vencedora_id from public.rodadas_votacao where id = '<rodada-sem-candidatas>';
-- deve ser null
```

## Resultados da validação (2026-07-24)

Cenários 1-10 automatizados e verdes (111/111 testes, `flutter test`, contra
Postgres+Auth local via `supabase start`):

- US1: `test/integration/rodada_abrir_participante_test.dart`,
  `test/integration/candidata_propor_test.dart`,
  `test/unit/rodada_model_test.dart`
- US2: `test/integration/voto_revogavel_test.dart`,
  `test/integration/votar_participante_test.dart`
- US3: `test/integration/fechamento_preguicoso_test.dart`,
  `test/integration/forcar_fechamento_dono_test.dart`,
  `test/integration/apuracao_empate_test.dart`,
  `test/integration/apuracao_vencedora_test.dart`,
  `test/integration/apuracao_sem_candidata_test.dart`
- US4: `test/integration/candidata_confirmar_presenca_test.dart`,
  `test/integration/apuracao_presenca_test.dart`
- US5: `test/integration/cancelar_acao_grupo_test.dart`

`flutter build macos --debug` confirma que o app compila e empacota com as
quatro features (001+002+003+004) juntas.

**Mesma lacuna conhecida das features anteriores**: SC-001/SC-002 (tempo de
abrir Rodada+propor, tempo de refletir troca de voto) não foram
cronometrados em dispositivo real — ambiente de build sem display
disponível.

**Lacuna adicional (documentada, não testada)**: o teste de empate
(`apuracao_empate_test.dart`) confirma que o sorteio sempre escolhe uma
candidata dentre as empatadas e descarta a outra corretamente, mas não
testa a distribuição estatística do sorteio ao longo de muitas rodadas
(não é uma garantia de fairness, só de corretude) — coerente com o que
research.md já registrava como fora de escopo.
