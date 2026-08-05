import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/grupo.dart';
import '../grupo_providers.dart';

/// Criação de Grupo (User Story 1). Quem cria vira Dono automaticamente
/// (garantido pelo trigger `grupos_dono_vira_participante` no banco).
class CriarGrupoPage extends ConsumerStatefulWidget {
  const CriarGrupoPage({super.key});

  @override
  ConsumerState<CriarGrupoPage> createState() => _CriarGrupoPageState();
}

class _CriarGrupoPageState extends ConsumerState<CriarGrupoPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _categoriaController = TextEditingController();
  final _categoriaFocusNode = FocusNode();
  final _detalhesController = TextEditingController();
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _nomeController.dispose();
    _categoriaController.dispose();
    _categoriaFocusNode.dispose();
    _detalhesController.dispose();
    super.dispose();
  }

  NovoGrupo get _grupoAtual {
    return NovoGrupo(
      nome: _nomeController.text,
      categoria: _categoriaController.text,
      detalhes: _detalhesController.text,
    );
  }

  Future<void> _criar() async {
    final grupo = _grupoAtual;
    if (_formKey.currentState?.validate() != true || !grupo.prontoParaEnviar) {
      setState(() => _erro = 'Preencha nome e Categoria.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await ref.read(grupoRepositoryProvider).criarGrupo(grupo);
      ref.invalidate(gruposProvider);
      if (mounted) context.pop();
    } catch (_) {
      setState(() => _erro = 'Não deu pra criar o Grupo agora. Tente de novo.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriasAsync = ref.watch(categoriasGrupoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Criar Grupo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nomeController,
                decoration: const InputDecoration(labelText: 'Nome do Grupo'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe um nome' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              categoriasAsync.when(
                data: (categorias) => RawAutocomplete<String>(
                  textEditingController: _categoriaController,
                  focusNode: _categoriaFocusNode,
                  optionsBuilder: (value) {
                    if (value.text.trim().isEmpty) {
                      return categorias.map((c) => c.nome);
                    }
                    return categorias
                        .map((c) => c.nome)
                        .where((nome) => nome.toLowerCase().contains(value.text.toLowerCase()));
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
                                  (nome) => ListTile(
                                    title: Text(nome),
                                    onTap: () => onSelected(nome),
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
                  controller: _categoriaController,
                  decoration: const InputDecoration(labelText: 'Categoria'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Informe uma Categoria' : null,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _detalhesController,
                decoration: const InputDecoration(labelText: 'Detalhes (opcional)'),
                maxLines: 3,
              ),
              if (_erro != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: _enviando ? null : _criar,
                child: _enviando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Criar Grupo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
