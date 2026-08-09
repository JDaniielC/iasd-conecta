import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/group.dart';
import '../group_providers.dart';

/// Criação de Grupo (User Story 1). Quem cria vira Dono automaticamente
/// (garantido pelo trigger `grupos_dono_vira_participante` no banco).
class CreateGroupPage extends ConsumerStatefulWidget {
  const CreateGroupPage({super.key});

  @override
  ConsumerState<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends ConsumerState<CreateGroupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _categoryFocusNode = FocusNode();
  final _detailsController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _categoryFocusNode.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  NewGroup get _currentGroup {
    return NewGroup(
      name: _nameController.text,
      category: _categoryController.text,
      details: _detailsController.text,
    );
  }

  Future<void> _submit() async {
    final group = _currentGroup;
    if (_formKey.currentState?.validate() != true || !group.isReadyToSubmit) {
      setState(() => _error = 'Preencha nome e Categoria.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(groupRepositoryProvider).createGroup(group);
      ref.invalidate(groupsProvider);
      if (mounted) context.pop();
    } catch (_) {
      setState(() => _error = 'Não deu pra criar o Grupo agora. Tente de novo.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(groupCategoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Criar Grupo/Ministério')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nome do Grupo/Ministério'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe um nome' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              categoriesAsync.when(
                data: (categories) => RawAutocomplete<String>(
                  textEditingController: _categoryController,
                  focusNode: _categoryFocusNode,
                  optionsBuilder: (value) {
                    if (value.text.trim().isEmpty) {
                      return categories.map((c) => c.name);
                    }
                    return categories
                        .map((c) => c.name)
                        .where((name) => name.toLowerCase().contains(value.text.toLowerCase()));
                  },
                  fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Categoria',
                        helperText: 'Escolha uma sugestão ou digite livremente',
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Informe uma Categoria' : null,
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView(
                            shrinkWrap: true,
                            children: options
                                .map(
                                  (name) => ListTile(
                                    title: Text(name),
                                    onTap: () => onSelected(name),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => TextFormField(
                  controller: _categoryController,
                  decoration: const InputDecoration(labelText: 'Categoria'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Informe uma Categoria' : null,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _detailsController,
                decoration: const InputDecoration(labelText: 'Detalhes (opcional)'),
                maxLines: 3,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Criar Grupo/Ministério'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
