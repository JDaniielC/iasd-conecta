import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../district_admin_providers.dart';

/// Gerenciar a lista de Igrejas do distrito (User Story 2): adicionar,
/// arquivar. Só acessível a Administrador do distrito — RLS de `igrejas`
/// já garante isso no banco (esta tela é só a UI sobre a regra).
class ManageChurchesPage extends ConsumerStatefulWidget {
  const ManageChurchesPage({super.key});

  @override
  ConsumerState<ManageChurchesPage> createState() => _ManageChurchesPageState();
}

class _ManageChurchesPageState extends ConsumerState<ManageChurchesPage> {
  final _nameController = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(districtAdminRepositoryProvider).addChurch(name);
      ref.invalidate(churchesProvider);
      _nameController.clear();
    } catch (_) {
      setState(() => _error = 'Não deu pra adicionar agora.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _archive(String churchId) async {
    try {
      await ref.read(districtAdminRepositoryProvider).archiveChurch(churchId);
      ref.invalidate(churchesProvider);
    } catch (_) {
      setState(() => _error = 'Não deu pra arquivar agora.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final churchesAsync = ref.watch(churchesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Igrejas do Distrito')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Nova Igreja'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton(
                  onPressed: _sending ? null : _add,
                  child: const Text('Adicionar'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: churchesAsync.when(
                data: (churches) => ListView(
                  children: churches
                      .map(
                        (church) => ListTile(
                          title: Text(church.name),
                          subtitle: church.isArchived ? const Text('Arquivada') : null,
                          trailing: church.isArchived
                              ? null
                              : TextButton(
                                  onPressed: () => _archive(church.id),
                                  child: const Text('Arquivar'),
                                ),
                        ),
                      )
                      .toList(),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const Text('Não deu pra carregar as igrejas agora.'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
