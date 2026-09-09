import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../legal_providers.dart';

/// Sob qual texto legal esta pessoa está, em "Meu Perfil".
///
/// Achado C-4 da convergência 1: `OutdatedConsentBanner` só renderiza quando há
/// divergência, então quem estava EM DIA não tinha onde ver a própria versão. A
/// tela de Perfil abre com "É tudo que o app guarda sobre você", e a base legal
/// do que ele guarda faz parte disso.
///
/// Versão desconhecida aparece como desconhecida. Escolher uma pela data seria
/// estimativa apresentada como registro — o mesmo palpite que a coluna existe
/// para evitar.
class AcceptedVersionLine extends ConsumerWidget {
  const AcceptedVersionLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(myConsentStatusProvider).value;
    if (status == null) return const SizedBox.shrink();

    final text = status.isUnknownVersion
        ? 'Seu aceite é anterior ao registro de versão, então a versão que '
              'você leu é desconhecida.'
        : 'Você aceitou a versão ${status.acceptedVersion} da Política de '
              'Privacidade e dos Termos de Uso.';

    return Text(text, style: Theme.of(context).textTheme.bodySmall);
  }
}
