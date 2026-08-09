/// Uma seção da lista (Grupos/Ações) — todos os itens de uma mesma Igreja,
/// pra render com um cabeçalho + `Divider` entre seções.
class ChurchSection<T> {
  const ChurchSection({required this.nomeIgreja, required this.itens});

  final String nomeIgreja;
  final List<T> itens;
}

/// Agrupa [itens] pela Igreja (via [igrejaIdDe]), usando [nomePorIgrejaId]
/// pra resolver o nome de exibição. Sem Igreja (`null`) ou Igreja arquivada/
/// invisível pro usuário atual (RLS) caem em seções à parte, sempre por
/// último — nessa ordem.
List<ChurchSection<T>> groupByChurch<T>(
  List<T> itens,
  String? Function(T) churchIdOf,
  Map<String, String> nameByChurchId,
) {
  const semIgreja = 'Sem Igreja';
  const hiddenChurch = 'Outra Igreja';

  final porNome = <String, List<T>>{};
  for (final item in itens) {
    final churchId = churchIdOf(item);
    final name = churchId == null
        ? semIgreja
        : _encurtarNomeIgreja(nameByChurchId[churchId] ?? hiddenChurch);
    porNome.putIfAbsent(name, () => []).add(item);
  }

  final nomes = porNome.keys.toList()
    ..sort((a, b) {
      if (a == b) return 0;
      if (a == semIgreja || a == hiddenChurch) return 1;
      if (b == semIgreja || b == hiddenChurch) return -1;
      return a.compareTo(b);
    });

  return nomes.map((name) => ChurchSection<T>(nomeIgreja: name, itens: porNome[name]!)).toList();
}

final _prefixoIgrejaAdventista = RegExp(
  r'^igreja\s+adventista(\s+d[aeo])?\s*',
  caseSensitive: false,
);

/// Tira o prefixo "Igreja Adventista (de/do/da)" do nome — no cabeçalho de
/// seção só interessa o que distingue uma Igreja da outra dentro do
/// distrito (ex.: "Igreja Adventista de Pombos" -> "Pombos").
String _encurtarNomeIgreja(String name) {
  final curto = name.replaceFirst(_prefixoIgrejaAdventista, '').trim();
  return curto.isEmpty ? name : curto;
}
