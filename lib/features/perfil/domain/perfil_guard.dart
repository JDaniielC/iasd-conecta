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
abstract final class PerfilGuard {
  /// Retorna `true` se a ação pode prosseguir (já tem Perfil). Se não tiver,
  /// navega pra `/cadastro` e retorna `false` — quem chama deve checar o
  /// retorno antes de continuar a ação.
  static bool exigirPerfil(BuildContext context, WidgetRef ref) {
    final hasPerfil = ref.read(hasPerfilProvider).valueOrNull ?? false;
    if (hasPerfil) return true;
    context.push('/cadastro');
    return false;
  }
}
