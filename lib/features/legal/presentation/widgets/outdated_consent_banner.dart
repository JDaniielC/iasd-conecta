import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../legal_providers.dart';

/// Aviso de que o texto legal mudou desde o aceite da pessoa.
///
/// Fecha `PENDENCIAS.md` 2.29. LGPD art. 8º, §6º: em alteração de forma ou
/// duração do tratamento, o controlador deve informar ao titular "com destaque
/// de forma específica do teor das alterações, podendo o titular ... revogá-lo
/// caso discorde".
///
/// **Destaque** é este cartão, no caminho normal de uso — não numa tela que a
/// pessoa precisa procurar, e não na tela de Novidades, cujo marcador de lido é
/// por instalação (quem reinstala nunca era alcançado).
///
/// **Teor** é a lista de mudanças, uma linha por versão. "Os termos mudaram"
/// tem destaque e não tem teor.
///
/// **NÃO BLOQUEIA O USO.** Consentimento obtido sob ameaça de perder o que já
/// se tinha não é livre. Quem fecha sem aceitar continua com tudo o que a
/// versão aceita já cobria; o que não recebe é o tratamento de finalidade nova.
class OutdatedConsentBanner extends ConsumerStatefulWidget {
  const OutdatedConsentBanner({super.key});

  @override
  ConsumerState<OutdatedConsentBanner> createState() =>
      _OutdatedConsentBannerState();
}

class _OutdatedConsentBannerState extends ConsumerState<OutdatedConsentBanner> {
  bool _dismissed = false;
  bool _saving = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(acceptCurrentLegalVersionProvider)();
      // Só invalida depois do sucesso. Invalidar antes esconderia o aviso de
      // quem não teve o aceite gravado.
      ref.invalidate(myConsentStatusProvider);
      if (mounted) setState(() => _dismissed = true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    // `.value` de um FutureProvider ainda carregando é nulo, e nulo aqui
    // significa "não há aviso". Um `??` que virasse `true` piscaria "seus
    // termos mudaram" para quem está em dia — defeito irmão do `ProfileGuard`
    // (`PENDENCIAS.md` 2.31).
    final status = ref.watch(myConsentStatusProvider).value;
    if (status == null || !status.isOutdated) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.all(AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'O texto legal mudou desde que você aceitou',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (status.isUnknownVersion)
              // Admitir a ignorância é o requisito, não uma falha de UX: o
              // aceite antigo não registrou versão, e escolher uma pela data
              // seria estimativa apresentada como registro.
              const Text(
                'Seu aceite é anterior ao registro de versão, então não '
                'sabemos qual versão você leu. Vale a pena ler o texto atual.',
              )
            else ...[
              Text('Você aceitou a versão ${status.acceptedVersion}. '
                  'A versão atual é a ${status.currentVersion}.'),
              const SizedBox(height: AppSpacing.sm),
              for (final change in status.changesSinceAccepted)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text('• $change'),
                ),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => context.push('/privacidade'),
              child: const Text('Ler a Política de Privacidade'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            // `OverflowBar` e não `Row`: em 360 px de largura — que é a que o
            // repo usa nos testes, e a que a maioria das pessoas do distrito
            // tem na mão — os dois botões lado a lado estouram por 9,6 px.
            // Aqui eles empilham em vez de vazar.
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: AppSpacing.sm,
              children: [
                TextButton(
                  onPressed:
                      _saving ? null : () => setState(() => _dismissed = true),
                  child: const Text('Agora não'),
                ),
                FilledButton(
                  onPressed: _saving ? null : _accept,
                  child: const Text('Aceitar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
