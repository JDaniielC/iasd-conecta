import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/leadership_declaration.dart';
import '../leadership_providers.dart';

/// Autodeclaração de Líder/Diretor de Ministério pro ano corrente (User
/// Story 1). FR-002: exige Conta — Perfil sozinho não basta, checado antes
/// de chamar a RPC (que também recusa, mas aqui evita a viagem ao banco e
/// direciona pro upgrade).
class DeclareLeadershipPage extends ConsumerStatefulWidget {
  const DeclareLeadershipPage({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<DeclareLeadershipPage> createState() => _DeclareLeadershipPageState();
}

class _DeclareLeadershipPageState extends ConsumerState<DeclareLeadershipPage> {
  bool _sending = false;
  String? _error;

  Future<void> _declare() async {
    if (!ref.read(authRepositoryProvider).hasAccount) {
      context.push('/upgrade-conta');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(leadershipRepositoryProvider).declare(
            groupId: widget.groupId,
            year: DateTime.now().year,
          );
      ref.invalidate(myDeclarationProvider(widget.groupId));
    } catch (_) {
      setState(() => _error = 'Não deu pra autodeclarar. Tente de novo.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final declarationAsync = ref.watch(myDeclarationProvider(widget.groupId));

    return Scaffold(
      appBar: AppBar(title: const Text('Líder/Diretor de Ministério')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Autodeclarar Líder/Diretor deste Grupo pro ano corrente. '
              'O Administrador do distrito confirma antes de valer.',
            ),
            const SizedBox(height: AppSpacing.lg),
            declarationAsync.when(
              data: (declaration) => _StatusView(declaration: declaration),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Text('Não deu pra carregar sua declaração.'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: _sending ? null : _declare,
              child: _sending
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Autodeclarar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({required this.declaration});

  final LeadershipDeclaration? declaration;

  @override
  Widget build(BuildContext context) {
    if (declaration == null) return const Text('Você ainda não se autodeclarou esse ano.');
    final texto = switch (declaration!.status) {
      LeadershipStatus.pending => 'Sua declaração está pendente de confirmação.',
      LeadershipStatus.confirmed => 'Sua declaração já foi confirmada.',
      LeadershipStatus.rejected => 'Sua declaração foi rejeitada. Autodeclarar de novo reabre a análise.',
    };
    return Text(texto);
  }
}
