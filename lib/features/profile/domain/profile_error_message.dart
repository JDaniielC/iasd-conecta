import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduz a recusa do banco para a frase que a pessoa lê.
///
/// Vive fora das telas porque cadastro e edição de Perfil batem nas **mesmas
/// três constraints**, e duas cópias destas frases é como uma tela passa a
/// explicar a recusa e a outra passa a dizer só "não deu". A frase genérica
/// vem por parâmetro, porque aí sim as duas dizem coisas diferentes: uma não
/// concluiu um cadastro, a outra não salvou uma correção.
String profileErrorMessage(
  PostgrestException error, {
  required String fallback,
}) {
  if (error.message.contains('nome_valido')) {
    return 'Esse nome não pode ser usado. Tente outro.';
  }
  if (error.message.contains('apelido_obrigatorio_menor')) {
    return 'Menores de idade precisam definir um Apelido.';
  }
  if (error.message.contains('consentimento_igreja_destacado')) {
    return 'Marque o consentimento específico para usar a igreja de origem.';
  }
  return fallback;
}
