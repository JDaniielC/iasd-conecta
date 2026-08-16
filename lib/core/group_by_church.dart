/// Uma seção da lista (Grupos/Ações) — todos os itens de uma mesma Igreja,
/// pra render com um cabeçalho + `Divider` entre seções.
class ChurchSection<T> {
  const ChurchSection({required this.churchName, required this.items});

  final String churchName;
  final List<T> items;
}

/// Agrupa [itens] pela Igreja (via [igrejaIdDe]), usando [nomePorIgrejaId]
/// pra resolver o nome de exibição. Sem Igreja (`null`) ou Igreja arquivada/
/// invisível pro usuário atual (RLS) caem em seções à parte, sempre por
/// último — nessa ordem.
List<ChurchSection<T>> groupByChurch<T>(
  List<T> items,
  String? Function(T) churchIdOf,
  Map<String, String> nameByChurchId,
) {
  const withoutChurch = 'Sem Igreja';
  const hiddenChurch = 'Outra Igreja';

  final byName = <String, List<T>>{};
  for (final item in items) {
    final churchId = churchIdOf(item);
    final name = churchId == null
        ? withoutChurch
        : _shortenChurchName(nameByChurchId[churchId] ?? hiddenChurch);
    byName.putIfAbsent(name, () => []).add(item);
  }

  final names = byName.keys.toList()
    ..sort((a, b) {
      if (a == b) return 0;
      if (a == withoutChurch || a == hiddenChurch) return 1;
      if (b == withoutChurch || b == hiddenChurch) return -1;
      return a.compareTo(b);
    });

  return names.map((name) => ChurchSection<T>(churchName: name, items: byName[name]!)).toList();
}

final _adventistChurchPrefix = RegExp(
  r'^igreja\s+adventista(\s+d[aeo])?\s*',
  caseSensitive: false,
);

/// Tira o prefixo "Igreja Adventista (de/do/da)" do nome — no cabeçalho de
/// seção só interessa o que distingue uma Igreja da outra dentro do
/// distrito (ex.: "Igreja Adventista de Pombos" -> "Pombos").
String _shortenChurchName(String name) {
  final shortened = name.replaceFirst(_adventistChurchPrefix, '').trim();
  return shortened.isEmpty ? name : shortened;
}
