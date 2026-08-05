/// Uma seção da lista (Grupos/Ações) — todos os itens de uma mesma Igreja,
/// pra render com um cabeçalho + `Divider` entre seções.
class SecaoPorIgreja<T> {
  const SecaoPorIgreja({required this.nomeIgreja, required this.itens});

  final String nomeIgreja;
  final List<T> itens;
}

/// Agrupa [itens] pela Igreja (via [igrejaIdDe]), usando [nomePorIgrejaId]
/// pra resolver o nome de exibição. Sem Igreja (`null`) ou Igreja arquivada/
/// invisível pro usuário atual (RLS) caem em seções à parte, sempre por
/// último — nessa ordem.
List<SecaoPorIgreja<T>> agruparPorIgreja<T>(
  List<T> itens,
  String? Function(T) igrejaIdDe,
  Map<String, String> nomePorIgrejaId,
) {
  const semIgreja = 'Sem Igreja';
  const igrejaInvisivel = 'Outra Igreja';

  final porNome = <String, List<T>>{};
  for (final item in itens) {
    final igrejaId = igrejaIdDe(item);
    final nome = igrejaId == null
        ? semIgreja
        : _encurtarNomeIgreja(nomePorIgrejaId[igrejaId] ?? igrejaInvisivel);
    porNome.putIfAbsent(nome, () => []).add(item);
  }

  final nomes = porNome.keys.toList()
    ..sort((a, b) {
      if (a == b) return 0;
      if (a == semIgreja || a == igrejaInvisivel) return 1;
      if (b == semIgreja || b == igrejaInvisivel) return -1;
      return a.compareTo(b);
    });

  return nomes.map((nome) => SecaoPorIgreja<T>(nomeIgreja: nome, itens: porNome[nome]!)).toList();
}

final _prefixoIgrejaAdventista = RegExp(
  r'^igreja\s+adventista(\s+d[aeo])?\s*',
  caseSensitive: false,
);

/// Tira o prefixo "Igreja Adventista (de/do/da)" do nome — no cabeçalho de
/// seção só interessa o que distingue uma Igreja da outra dentro do
/// distrito (ex.: "Igreja Adventista de Pombos" -> "Pombos").
String _encurtarNomeIgreja(String nome) {
  final curto = nome.replaceFirst(_prefixoIgrejaAdventista, '').trim();
  return curto.isEmpty ? nome : curto;
}
