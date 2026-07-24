import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../district_admin_providers.dart';

/// Promover outro Usuário a Administrador do distrito (User Story 1).
///
/// Sem busca por nome — quem promove informa o ID do Perfil diretamente
/// (ver research.md: construir um diretório de busca é escopo maior que o
/// pedido nesta feature).
class PromoteAdminPage extends ConsumerStatefulWidget {
  const PromoteAdminPage({super.key});

  @override
  ConsumerState<PromoteAdminPage> createState() => _PromoteAdminPageState();
}

class _PromoteAdminPageState extends ConsumerState<PromoteAdminPage> {
  final _idController = TextEditingController();
  bool _sending = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  Future<void> _promote() async {
    final targetId = _idController.text.trim();
    if (targetId.isEmpty) {
      setState(() => _error = 'Informe o ID do Perfil.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _success = null;
    });
    try {
      await ref.read(districtAdminRepositoryProvider).promoteToAdmin(targetId);
      setState(() => _success = 'Promovido a Administrador do distrito.');
      _idController.clear();
    } catch (_) {
      setState(
        () => _error =
            'Não deu pra promover. Confirme que o ID existe e que essa pessoa já tem Conta.',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Promover Administrador')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'A pessoa promovida precisa já ter Conta (upgrade de Perfil) — '
              'Perfil sozinho não é suficiente.',
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _idController,
              decoration: const InputDecoration(labelText: 'ID do Perfil'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_success != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_success!),
            ],
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: _sending ? null : _promote,
              child: _sending
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Promover'),
            ),
          ],
        ),
      ),
    );
  }
}
