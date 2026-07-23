/// Pré-checagem client-side da moderação de nome — só feedback imediato na
/// UI. A fonte de verdade é a função `public.nome_valido` no banco
/// (constraint `nome_valido(nome)` em `perfis`); esta lista é uma cópia
/// cacheada, não uma reimplementação de moderação (ver research.md).
class NomeModeration {
  const NomeModeration(this._palavrasBloqueadas);

  final List<String> _palavrasBloqueadas;

  bool valido(String nome) {
    final normalizado = _normalizar(nome);
    return !_palavrasBloqueadas
        .map(_normalizar)
        .any(normalizado.contains);
  }

  static String _normalizar(String texto) => texto.toLowerCase();
}
