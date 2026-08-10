/// Pré-checagem client-side da moderação de nome — só feedback imediato na
/// UI. A fonte de verdade é a função `public.nome_valido` no banco
/// (constraint `nome_valido(nome)` em `perfis`); esta lista é uma cópia
/// cacheada, não uma reimplementação de moderação (ver research.md).
class NameModeration {
  const NameModeration(this._blockedWords);

  /// A mesma lista que antes era literal dentro da tela de cadastro.
  ///
  /// Ela vive aqui para que cadastro e edição de Perfil não possam divergir:
  /// duas cópias da mesma lista é como uma tela passa a recusar um nome que a
  /// outra aceita, sem ninguém perceber.
  static const cached = NameModeration([
    'idiota',
    'burro',
    'estupido',
    'imbecil',
    'babaca',
  ]);

  final List<String> _blockedWords;

  bool isValid(String name) {
    final normalizado = _normalize(name);
    return !_blockedWords
        .map(_normalize)
        .any(normalizado.contains);
  }

  static String _normalize(String texto) => texto.toLowerCase();
}
