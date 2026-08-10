import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/consent_tally.dart';
import '../legal_providers.dart';

/// Quantas pessoas estão sob cada versão do texto legal (feature 017, US2).
///
/// Tela só de leitura, sem nenhuma ação: ela responde uma pergunta de
/// conformidade, não gerencia nada. Mostra contagem, nunca identidade — quem é
/// cada pessoa não é assunto desta pergunta (Princípio II).
///
/// Fica em `features/legal/` porque o assunto é o consentimento;
/// `district_admin/` é sobre gerir Igreja e promover Administrador.
class ConsentVersionsPage extends ConsumerWidget {
  const ConsentVersionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tallyAsync = ref.watch(consentTallyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Versões de consentimento')),
      body: tallyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Text('Não deu pra carregar agora.'),
          ),
        ),
        data: (tallies) => ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            for (final kind in ConsentKind.values)
              _KindSection(
                kind: kind,
                tallies: tallies.where((t) => t.kind == kind).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _KindSection extends StatelessWidget {
  const _KindSection({required this.kind, required this.tallies});

  final ConsentKind kind;
  final List<ConsentTally> tallies;

  String get _title => switch (kind) {
        ConsentKind.lgpd => 'Consentimento LGPD',
        ConsentKind.church => 'Consentimento de Igreja de origem',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Versão desconhecida por último: ela é a exceção, não o normal.
    final sorted = [...tallies]..sort((a, b) {
        if (a.isVersionUnknown != b.isVersionUnknown) {
          return a.isVersionUnknown ? 1 : -1;
        }
        return (a.consentedVersion ?? '').compareTo(b.consentedVersion ?? '');
      });
    final hasUnknown = sorted.any((t) => t.isVersionUnknown);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_title, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (sorted.isEmpty)
            const Text('Nenhum aceite registrado.')
          else
            for (final tally in sorted)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  tally.isVersionUnknown
                      ? 'Versão desconhecida — ${tally.count} '
                          '${tally.count == 1 ? 'pessoa' : 'pessoas'}'
                      : 'Versão ${tally.consentedVersion} — ${tally.count} '
                          '${tally.count == 1 ? 'pessoa' : 'pessoas'}',
                ),
              ),
          if (hasUnknown) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Versão desconhecida são aceites colhidos antes de o app passar '
              'a registrar qual texto foi aceito. O número não é um palpite '
              'sobre qual versão era — é o registro de que não dá para saber.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
