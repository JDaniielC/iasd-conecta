import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';

/// Gate reusado por toda ação que exige Perfil (Participar, Criar Grupo,
/// etc. — FR-008/FR-009 da feature 001).
///
/// Diferente do redirect global do router: aqui a pessoa PODE navegar
/// livremente como Visitante (`lib/app.dart` não força `/cadastro`); só ao
/// tentar uma ação concreta ela é direcionada ao cadastro.
abstract final class ProfileGuard {
  /// Retorna `true` se a ação pode prosseguir (já tem Perfil). Se não tiver,
  /// navega pra `/cadastro` e retorna `false` — quem chama deve checar o
  /// retorno antes de continuar a ação.
  ///
  /// **Espera a resposta chegar, e é por isso que é assíncrono.** A versão
  /// anterior lia `ref.read(hasProfileProvider).value ?? false`: um
  /// `FutureProvider` que ninguém leu antes nasce `AsyncLoading`, `.value` é
  /// `null`, e o guard respondia "não tem Perfil" sobre uma pergunta ainda sem
  /// resposta — mandando ao cadastro quem já tinha cadastro.
  ///
  /// Não quebrava em produção porque `lib/app.dart` faz
  /// `ref.listen(hasProfileProvider, ...)` no arranque do router e o provider
  /// não é `autoDispose`, então na prática ele já estava resolvido. A correção
  /// morava naquela linha, num arquivo que ninguém tem motivo para associar a
  /// este. Ver PENDENCIAS § 2.31.
  static Future<bool> requireProfile(BuildContext context, WidgetRef ref) async {
    final hasProfile = await ref.read(hasProfileProvider.future);
    if (hasProfile) return true;
    // A tela pode ter saído da árvore durante a espera.
    if (!context.mounted) return false;
    context.push('/cadastro');
    return false;
  }
}
