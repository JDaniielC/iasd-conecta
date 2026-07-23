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
  final _horarioController = TextEditingController();
  final _localController = TextEditingController();
  final _detalhesController = TextEditingController();
  String? _categoria;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _nomeController.dispose();
    _horarioController.dispose();
    _localController.dispose();
    _detalhesController.dispose();
    super.dispose();
  }

  NovoGrupo? get _grupoAtual {
    if (_categoria == null) return null;
    return NovoGrupo(
      nome: _nomeController.text,
      categoria: _categoria!,
      horario: _horarioController.text,
      local: _localController.text,
      detalhes: _detalhesController.text,
    );
  }

  Future<void> _criar() async {
    final grupo = _grupoAtual;
    if (_formKey.currentState?.validate() != true || grupo == null || !grupo.prontoParaEnviar) {
      setState(() => _erro = 'Preencha nome, Categoria, horário e local.');
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
                data: (categorias) => DropdownButtonFormField<String>(
                  initialValue: _categoria,
                  decoration: const InputDecoration(labelText: 'Categoria'),
                  items: categorias
                      .map((c) => DropdownMenuItem(value: c.nome, child: Text(c.nome)))
                      .toList(),
                  onChanged: (v) => setState(() => _categoria = v),
                  validator: (v) => (v == null || v.isEmpty) ? 'Escolha uma Categoria' : null,
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const Text('Não deu pra carregar as categorias agora.'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _horarioController,
                decoration: const InputDecoration(
                  labelText: 'Horário padrão de encontro',
                  helperText: 'ex.: sábados às 16h',
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o horário' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _localController,
                decoration: const InputDecoration(labelText: 'Local'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o local' : null,
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
