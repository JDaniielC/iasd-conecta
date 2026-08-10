import 'package:supabase_flutter/supabase_flutter.dart';

import '../../legal/legal_metadata.dart';
import 'profile.dart';

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
  if (error.message.contains('autorizacao_responsavel_crianca')) {
    // Duas situações caem aqui, e a frase precisa servir às duas: um cadastro
    // novo de criança sem os dados do responsável, e — desde a feature 016 —
    // uma tentativa de EDITAR um Perfil de criança cadastrado antes da feature
    // 015, que ficou somente-leitura. A segunda é a que mais surpreende.
    return 'Cadastros de menores de $childAgeThreshold anos precisam dos dados '
        'de um responsável. Se este cadastro é antigo e você não consegue '
        'alterá-lo, escreva para ${LegalMetadata.contactEmail}.';
  }
  if (error.message.contains('autorizacao_responsavel_so_para_crianca')) {
    return 'Os dados de responsável só valem para menores de '
        '$childAgeThreshold anos. Confira a idade informada.';
  }
  if (error.message.contains('consentimento_igreja_destacado')) {
    return 'Marque o consentimento específico para usar a igreja de origem.';
  }
  return fallback;
}
