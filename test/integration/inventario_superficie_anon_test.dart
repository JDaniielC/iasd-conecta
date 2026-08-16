import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

/// Change `fechar-superficie-anon` — o INVENTÁRIO, e ele vale mais que os
/// consertos que o acompanham.
///
/// `anon` é a role que o PostgREST usa em requisição SEM `Authorization`, e a
/// chave que a alcança vai dentro do JavaScript publicado. O que ela alcança
/// nunca foi decidido: cresceu porque cada policy nova copiou a anterior, e
/// porque **função nova no Postgres nasce chamável por todo mundo**.
///
/// Este arquivo olha as TRÊS barreiras, e as três de propósito — fechar duas
/// deixa a terceira como o único obstáculo:
///
///   1. privilégio de `execute` em função
///   2. o papel a quem a policy de `select` é endereçada
///   3. o `grant select` na tabela
///   4. o mesmo par — policy e grant — para ESCREVER
///
/// A quarta veio da convergência: as três primeiras cobrem LEITURA, e a Purpose
/// da capability fala do que uma requisição sem sessão **alcança**. Escrever é
/// alcançar. Medido em 2026-08-16, `anon` insere em `denuncias_imagem` — e é de
/// propósito, mas nada olhava para lá.
///
/// A LISTA DE EXCEÇÕES MORA AQUI, escrita à mão, cada linha com o motivo. Não
/// se deriva do banco: um teste que perguntasse "o que está aberto hoje?" e
/// gravasse a resposta como esperada nunca falharia — ele carimbaria o defeito
/// junto com o resto. O ponto é a lista ter sido decidida por alguém.
///
/// Ele olha o PRIVILÉGIO, não o resultado — mesmo desenho de
/// `chat_privilegio_funcao_test.dart`. Um teste que conferisse só "anon não lê
/// mensagem" continuaria verde com a RPC aberta, porque são barreiras
/// diferentes.

/// Funções que PODEM ser chamadas sem sessão. Cada uma com o motivo, e a
/// ausência de motivo é o que reprova.
const _functionsOpenOnPurpose = <String, String>{
  // Devolve nome de exibição e Apelido. É o que faz um Grupo ter nomes na tela
  // antes de qualquer login, e devolve Apelido no lugar do nome quando a
  // pessoa é menor de idade — ou seja, ela já é a barreira.
  'perfil_publico(p_id uuid)': 'pública por desenho; já filtra menor de idade',

  // Puro cálculo sobre o argumento: não lê tabela nenhuma.
  'acao_encerrada(p_acao_id uuid)': 'cálculo de data, sem leitura de tabela',
  'acao_encerrada(p_data_hora timestamp with time zone)':
      'cálculo de data, sem leitura de tabela',

  // Devolve a constante de idade da feature 015. Está na Política de
  // Privacidade, que é pública.
  'limiar_crianca()': 'constante já publicada na Política de Privacidade',

  // Da extensão `unaccent`, pertencem a `supabase_admin`. Mexer no ACL delas
  // quebra a extensão, e elas não leem nada do schema.
  'unaccent(text)': 'da extensão, pertence a supabase_admin',
  'unaccent(regdictionary, text)': 'da extensão, pertence a supabase_admin',
  'unaccent_init(internal)': 'da extensão, pertence a supabase_admin',
  'unaccent_lexize(internal, internal, internal, internal)':
      'da extensão, pertence a supabase_admin',
};

/// Policies de `select` que PODEM endereçar `anon`. Vazio, e é o resultado:
/// nenhuma tela do app precisa de leitura sem sessão, porque o app sempre tem
/// sessão — `signInAnonymously` no arranque. Ver `superficie-sem-login`.
const _selectPoliciesOpenOnPurpose = <String, String>{};

/// Tabelas que PODEM ter `grant select` a `anon`. Vazio, pelo mesmo motivo.
const _tableGrantsOpenOnPurpose = <String, String>{};

/// Tabelas que PODEM aceitar ESCRITA sem sessão, e a única que aceita é
/// deliberada.
const _writesOpenOnPurpose = <String, String>{
  // FR-015 da feature 013: denunciar uma Foto de capa imprópria não exige
  // cadastro, porque exigir cadastro para denunciar foto de menor protegeria o
  // problema. A policy `denuncias_imagem_insert_qualquer` tem
  // `with check (denunciante_id is null or denunciante_id = auth.uid())`, então
  // quem escreve sem sessão não consegue assinar por outra pessoa.
  'denuncias_imagem': 'FR-015: denúncia de foto sem cadastro, por decisão',
};

void main() {
  late Connection conn;

  setUpAll(() async => conn = await openTestConnection());
  tearDownAll(() => conn.close());

  test('nenhuma função nova ficou chamável sem sessão', () async {
    final rows = await conn.execute('''
      select p.proname || '(' ||
             pg_get_function_identity_arguments(p.oid) || ')' as assinatura,
             p.prosecdef
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.prorettype <> 'trigger'::regtype
        and has_function_privilege('anon', p.oid, 'execute')
      order by 1
    ''');

    final reachable = {for (final r in rows) r[0]! as String: r[1]! as bool};
    final undeclared = reachable.keys
        .where((f) => !_functionsOpenOnPurpose.containsKey(f))
        .toList();

    expect(
      undeclared,
      isEmpty,
      reason:
          'Função alcançável sem sessão e sem motivo escrito. Se for de '
          'propósito, acrescente em `_functionsOpenOnPurpose` com o porquê; se '
          'não, `revoke execute ... from public` na migration ANTES do grant. '
          'Lembre que `proacl` NULO também é grant a PUBLIC.',
    );

    // A lista não pode envelhecer para o outro lado: exceção que já não existe
    // vira permissão dormente para uma função futura de mesmo nome.
    final staleExceptions = _functionsOpenOnPurpose.keys
        .where((f) => !reachable.containsKey(f))
        .toList();
    expect(
      staleExceptions,
      isEmpty,
      reason:
          'exceção declarada para função que não está mais aberta — tire '
          'da lista, senão ela autoriza a próxima com o mesmo nome',
    );
  });

  test('o `revoke` não levou junto quem precisa das funções', () async {
    // O CONTRAPESO, e sem ele o teste de cima passa pelo motivo errado: uma
    // função fechada para TODO MUNDO também não é alcançável por `anon`.
    //
    // Mesmo desenho de `chat_privilegio_funcao_test.dart`, e o mesmo
    // comentário vale — `revoke ... from public` acrescentado sem o `grant`
    // seguinte deixa a função inútil, o app quebra em produção, e o gate de
    // privilégio continua verde porque ele só pergunta sobre `anon`.
    //
    // A lista é das que esta change tocou, mais as declaradas: se `revoke` for
    // acrescentado a alguma delas por engano, aqui fica vermelho.
    const needsAuthenticated = [
      'public.autor_de_mudanca()',
      'public.nome_valido(text)',
      'public.versao_texto_legal_vigente()',
      'public.declarar_lideranca(uuid, integer)',
      'public.decidir_lideranca(uuid, boolean)',
      'public.fechar_rodada_se_devido(uuid, boolean)',
      'public.perfil_publico(uuid)',
    ];

    for (final signature in needsAuthenticated) {
      final r = await conn.execute(
        Sql.named(
          "select has_function_privilege('authenticated', @f, 'execute')",
        ),
        parameters: {'f': signature},
      );
      expect(
        r.first[0],
        isTrue,
        reason:
            '$signature ficou inalcançável para quem TEM sessão — o '
            '`revoke ... from public` precisa vir com o `grant` ao lado',
      );
    }
  });

  test('nenhuma policy de select endereça quem não tem sessão', () async {
    // `polroles = '{0}'` é PUBLIC — a policy sem `to` explícito, que alcança
    // todo mundo. Contada junto com `anon` de propósito: as duas formas têm o
    // mesmo efeito e só uma é visível no `create policy`.
    final rows = await conn.execute('''
      select c.relname || '.' || p.polname
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and p.polcmd in ('r', '*')
        and (p.polroles = '{0}'::oid[]
             or 'anon' = any(
               select rolname from pg_roles where oid = any(p.polroles)))
      order by 1
    ''');

    final reachable = rows.map((r) => r[0]! as String).toList();
    expect(
      reachable.where((p) => !_selectPoliciesOpenOnPurpose.containsKey(p)),
      isEmpty,
      reason:
          'Policy de select alcançando quem não tem sessão. O app nunca chega '
          'ao banco como `anon` — Visitante tem sessão. Troque para '
          '`to authenticated`, ou declare em `_selectPoliciesOpenOnPurpose` '
          'com o motivo.',
    );
  });

  test('nenhuma tabela concede select a quem não tem sessão', () async {
    // Terceira barreira, e ela sobrevive sozinha à queda das outras duas: um
    // grant esquecido espera só uma linha de policy escrita daqui a um ano.
    final rows = await conn.execute('''
      select table_name
      from information_schema.role_table_grants
      where table_schema = 'public'
        and grantee = 'anon'
        and privilege_type = 'SELECT'
      order by 1
    ''');

    final reachable = rows.map((r) => r[0]! as String).toList();
    expect(
      reachable.where((t) => !_tableGrantsOpenOnPurpose.containsKey(t)),
      isEmpty,
      reason:
          'Tabela com `grant select` a `anon`. Sem policy que o alcance ela '
          'não lê nada hoje — e é metade de um par cuja outra metade alguém '
          'escreve sem lembrar deste arquivo.',
    );
  });

  test('nenhuma tabela aceita ESCRITA de quem não tem sessão', () async {
    // Quarta barreira, e ela não estava aqui até a convergência. As três de
    // cima cobrem leitura; a Purpose da capability fala do que uma requisição
    // sem sessão ALCANÇA, e escrever é alcançar.
    //
    // Duas metades outra vez, e as duas precisam estar fechadas: o `grant` de
    // `insert`/`update`/`delete`, e a policy que endereça `anon`. Uma sozinha
    // não escreve nada — e é metade de um par cuja outra metade alguém
    // acrescenta sem lembrar deste arquivo.
    final grants = await conn.execute('''
      select distinct table_name
      from information_schema.role_table_grants
      where table_schema = 'public'
        and grantee = 'anon'
        and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
      order by 1
    ''');

    final policies = await conn.execute('''
      select distinct c.relname
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and p.polcmd in ('a', 'w', 'd')
        and (p.polroles = '{0}'::oid[]
             or 'anon' = any(
               select rolname from pg_roles where oid = any(p.polroles)))
      order by 1
    ''');

    final writable = <String>{
      for (final rows in [grants, policies])
        for (final r in rows) r[0]! as String,
    };

    expect(
      writable.where((t) => !_writesOpenOnPurpose.containsKey(t)),
      isEmpty,
      reason:
          'Tabela aceitando escrita de quem não tem sessão. Se for de '
          'propósito, acrescente em `_writesOpenOnPurpose` com o porquê — e '
          'confira que a policy tem `with check` impedindo assinar por '
          'outra pessoa.',
    );

    // O outro sentido, como na lista de funções: exceção para tabela que já
    // não aceita escrita vira permissão dormente para a próxima de mesmo nome.
    expect(
      _writesOpenOnPurpose.keys.where((t) => !writable.contains(t)),
      isEmpty,
      reason:
          'exceção declarada para tabela que não aceita mais escrita sem '
          'sessão — tire da lista',
    );
  });

  test('as listas de exceção têm o tamanho que se espera', () async {
    // Contagem explícita, e não é redundante com os testes acima: eles
    // reprovam o que está aberto FORA da lista. Se alguém acrescentar uma
    // exceção para calar um deles, este número muda e o diff mostra.
    expect(_functionsOpenOnPurpose, hasLength(8));
    expect(_selectPoliciesOpenOnPurpose, isEmpty);
    expect(_tableGrantsOpenOnPurpose, isEmpty);
    expect(_writesOpenOnPurpose, hasLength(1));

    // E toda exceção precisa de motivo não vazio — a lista existe por isso.
    for (final list in [_functionsOpenOnPurpose, _writesOpenOnPurpose]) {
      for (final e in list.entries) {
        expect(e.value.trim(), isNotEmpty, reason: e.key);
      }
    }
  });
}
