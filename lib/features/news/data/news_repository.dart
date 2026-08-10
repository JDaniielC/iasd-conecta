import 'package:shared_preferences/shared_preferences.dart';

/// Guarda até que data esta instalação já viu as Novidades.
///
/// **É o único estado que a feature persiste, e ele fica no aparelho** —
/// `localStorage` na web, preferências nativas no móvel. Nunca no servidor.
///
/// O caminho óbvio seria uma coluna em `perfis`: sobreviveria à troca de
/// aparelho e resolveria o incômodo de o aviso reaparecer. E criaria um dado de
/// comportamento — quando esta pessoa abriu o app, o que ela leu — que nenhuma
/// entrada do glossário autoriza e que nenhuma tela precisa. Num app que acabou
/// de passar três features fechando exposição, seria abrir uma porta nova pelo
/// conforto de não reapresentar um aviso.
///
/// O preço é conhecido e aceito: trocar de aparelho, reinstalar ou limpar o
/// navegador zera o marcador, e o aviso volta para itens já lidos.
class NewsRepository {
  const NewsRepository();

  /// Chave em português por ser dado de armazenamento, não identificador Dart.
  static const _lastSeenKey = 'novidades_ultima_vista';

  Future<DateTime?> readLastSeenDate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastSeenKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> writeLastSeenDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSeenKey, date.toUtc().toIso8601String());
  }
}
