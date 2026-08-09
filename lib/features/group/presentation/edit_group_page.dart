import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../group_providers.dart';

/// Administração do Grupo pelo Dono (User Story 3): editar campos, remover
/// participante, transferir posse. RLS + triggers no banco são a garantia
/// real (FR-009/010/011/012); esta tela é só a UI sobre isso.
class EditGroupPage extends ConsumerStatefulWidget {
  const EditGroupPage({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<EditGroupPage> createState() => _EditGroupPageState();
}

class _EditGroupPageState extends ConsumerState<EditGroupPage> {
  final _nameController = TextEditingController();
  final _detailsController = TextEditingController();
  bool _carregouCampos = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await ref.read(groupRepositoryProvider).updateGroup(
            widget.groupId,
            name: _nameController.text,
            details: _detailsController.text,
          );
      ref.invalidate(groupProvider(widget.groupId));
      ref.invalidate(groupsProvider);
      if (mounted) context.pop();
    } catch (_) {
      setState(() => _error = 'Não deu pra salvar. Você ainda é o Dono deste Grupo?');
    }
  }

  Future<void> _removeMember(String userId) async {
    try {
      await ref.read(groupRepositoryProvider).removeMember(widget.groupId, userId);
      ref.invalidate(membersProvider(widget.groupId));
    } catch (_) {
      setState(() => _error = 'Não deu pra remover esse participante.');
    }
  }

  Future<void> _transferOwnership(String newOwnerId) async {
    try {
      await ref.read(groupRepositoryProvider).transferOwnership(widget.groupId, newOwnerId);
      ref.invalidate(groupProvider(widget.groupId));
      if (mounted) context.pop();
    } catch (_) {
      setState(() => _error = 'Não deu pra transferir a posse.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupProvider(widget.groupId));
    final membersAsync = ref.watch(membersProvider(widget.groupId));
    final uid = ref.watch(currentUserIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Editar Grupo')),
      body: groupAsync.when(
        data: (group) {
          if (!group.isOwner(uid)) {
            return const Center(child: Text('Você não é o Dono deste Grupo.'));
          }
          if (!_carregouCampos) {
            _nameController.text = group.name;
            _detailsController.text = group.details ?? '';
            _carregouCampos = true;
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _detailsController,
                  decoration: const InputDecoration(labelText: 'Detalhes'),
                  maxLines: 3,
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton(onPressed: _save, child: const Text('Salvar')),
                const SizedBox(height: AppSpacing.lg),
                Text('Participantes', style: Theme.of(context).textTheme.titleLarge),
                membersAsync.when(
                  data: (members) => Column(
                    children: members.map((p) {
                      final isTheOwner = p.id == group.ownerId;
                      return ListTile(
                        title: Text(p.displayName),
                        subtitle: isTheOwner ? const Text('Dono') : null,
                        trailing: isTheOwner
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () => _transferOwnership(p.id),
                                    child: const Text('Tornar Dono'),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.person_remove_outlined),
                                    onPressed: () => _removeMember(p.id),
                                  ),
                                ],
                              ),
                      );
                    }).toList(),
                  ),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const Text('Não deu pra carregar os participantes.'),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Grupo não encontrado.')),
      ),
    );
  }
}
