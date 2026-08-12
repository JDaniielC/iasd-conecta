import 'package:shared_preferences/shared_preferences.dart';

/// Guarda a última vez que esta instalação abriu `/acoes`.
///
/// Gêmeo de `NewsRepository`, e pelo mesmo motivo: é o único estado que o
/// destaque persiste, e ele fica no aparelho — `localStorage` na web,
/// preferências nativas no móvel. Nunca no servidor. Uma coluna em `perfis`
/// sobreviveria à troca de aparelho e criaria um dado de comportamento
/// (quando esta pessoa abriu a lista de Ações) que nenhuma entrada do
/// glossário autoriza e que nenhuma tela precisa.
///
/// Classe própria, e não um método em `ActionRepository`: aquele repositório
/// exige um `SupabaseClient` no construtor, o que tornaria este marcador —
/// que nunca fala com o servidor — impossível de substituir em teste de
/// widget sem mockar o cliente inteiro.
///
/// O preço é o mesmo de Novidades: reinstalar ou limpar o navegador zera o
/// marcador, e Ação de Grupo já vista pode voltar ao destaque uma vez.
class ActionsSeenRepository {
  const ActionsSeenRepository();

  /// Chave em português por ser dado de armazenamento, não identificador Dart.
  static const _lastSeenKey = 'acoes_ultima_vista';

  Future<DateTime?> readLastSeenActionsDate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastSeenKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> writeLastSeenActionsDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSeenKey, date.toUtc().toIso8601String());
  }
}
