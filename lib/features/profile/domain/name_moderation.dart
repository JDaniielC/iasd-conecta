/// Pré-checagem client-side da moderação de nome — só feedback imediato na
/// UI. A fonte de verdade é a função `public.nome_valido` no banco
/// (constraint `nome_valido(nome)` em `perfis`); esta lista é uma cópia
/// cacheada, não uma reimplementação de moderação (ver research.md).
class NameModeration {
  const NameModeration(this._blockedWords);

  final List<String> _blockedWords;

  bool isValid(String name) {
    final normalizado = _normalize(name);
    return !_blockedWords
        .map(_normalize)
        .any(normalizado.contains);
  }

  static String _normalize(String texto) => texto.toLowerCase();
}
