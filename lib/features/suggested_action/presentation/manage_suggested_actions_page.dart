import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../group/group_providers.dart';
import '../suggested_action_providers.dart';

/// Gerenciar a lista de Ações sugeridas (User Story 3): cadastrar,
/// remover. Só acessível a Administrador do distrito — RLS de
/// `acoes_sugeridas` já garante isso no banco (esta tela é só a UI sobre
/// a regra).
class ManageSuggestedActionsPage extends ConsumerStatefulWidget {
  const ManageSuggestedActionsPage({super.key});

  @override
  ConsumerState<ManageSuggestedActionsPage> createState() =>
      _ManageSuggestedActionsPageState();
}

class _ManageSuggestedActionsPageState extends ConsumerState<ManageSuggestedActionsPage> {
  final _nameController = TextEditingController();
  String? _categoryId;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _categoryId == null) {
      setState(() => _error = 'Escolha uma Categoria e informe um nome.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(suggestedActionRepositoryProvider)
          .create(categoryId: _categoryId!, name: name);
      ref.invalidate(allSuggestedActionsProvider);
      _nameController.clear();
    } catch (_) {
      setState(() => _error = 'Não deu pra cadastrar agora.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(String id) async {
    try {
      await ref.read(suggestedActionRepositoryProvider).delete(id);
      ref.invalidate(allSuggestedActionsProvider);
    } catch (_) {
      setState(() => _error = 'Não deu pra remover agora.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(groupCategoriesProvider);
    final suggestionsAsync = ref.watch(allSuggestedActionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ações Sugeridas')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            categoriesAsync.when(
              data: (categories) => DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: categories
                    .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                    .toList(),
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Text('Não deu pra carregar as categorias.'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Nova Ação sugerida'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton(
                  onPressed: _sending ? null : _create,
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
              child: categoriesAsync.when(
                data: (categories) => suggestionsAsync.when(
                  data: (suggestions) {
                    final categoryName = {for (final c in categories) c.id: c.name};
                    return ListView(
                      children: suggestions
                          .map(
                            (s) => ListTile(
                              title: Text(s.name),
                              subtitle: Text(categoryName[s.categoryId] ?? ''),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(s.id),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const Text('Não deu pra carregar as sugestões.'),
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const Text('Não deu pra carregar as categorias.'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
