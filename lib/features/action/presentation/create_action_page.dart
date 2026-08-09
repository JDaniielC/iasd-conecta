import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../suggested_action/suggested_action_providers.dart';
import '../../group/group_providers.dart';
import '../action_providers.dart';
import '../domain/action.dart';

/// Criação de Ação avulsa (User Story 1). Já nasce confirmada, sem
/// votação; o criador vira confirmado automaticamente (trigger no banco).
class CreateActionPage extends ConsumerStatefulWidget {
  const CreateActionPage({super.key});

  @override
  ConsumerState<CreateActionPage> createState() => _CreateActionPageState();
}

class _CreateActionPageState extends ConsumerState<CreateActionPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _localController = TextEditingController();
  final _detalhesController = TextEditingController();
  final _limiteVagasController = TextEditingController();
  DateTime? _dataHora;
  bool _enviando = false;
  String? _erro;
  bool _isMissionaryPair = false;
  VisitedGender? _visitedGender;
  String? _categoriaFiltroId;

  @override
  void dispose() {
    _nomeController.dispose();
    _localController.dispose();
    _detalhesController.dispose();
    _limiteVagasController.dispose();
    super.dispose();
  }

  Future<void> _escolherDataHora() async {
    final agora = DateTime.now();
    final data = await showDatePicker(
      context: context,
      initialDate: agora,
      firstDate: agora,
      lastDate: agora.add(const Duration(days: 365 * 2)),
    );
    if (data == null || !mounted) return;
    final hora = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (hora == null) return;
    setState(() {
      _dataHora = DateTime(data.year, data.month, data.day, hora.hour, hora.minute);
    });
  }

  NewAction? get _acaoAtual {
    if (_dataHora == null) return null;
    return NewAction(
      name: _nomeController.text,
      dateTime: _dataHora!,
      local: _localController.text,
      details: _detalhesController.text,
      capacity: int.tryParse(_limiteVagasController.text),
      isMissionaryPair: _isMissionaryPair,
      visitedGender: _visitedGender,
    );
  }

  Future<void> _criar() async {
    final acao = _acaoAtual;
    if (_formKey.currentState?.validate() != true || acao == null || !acao.isReadyToSubmit) {
      setState(() => _erro = 'Preencha nome, data/hora e local.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await ref.read(actionRepositoryProvider).createAction(acao);
      ref.invalidate(actionsProvider);
      if (mounted) context.pop();
    } catch (_) {
      setState(() => _erro = 'Não deu pra criar a Ação agora. Tente de novo.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriasAsync = ref.watch(groupCategoriesProvider);
    final suggestionsAsync = _categoriaFiltroId == null
        ? null
        : ref.watch(suggestionsForCategoryProvider(_categoriaFiltroId!));
    final suggestions = suggestionsAsync?.value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Criar Ação')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              categoriasAsync.when(
                data: (categorias) => DropdownButtonFormField<String>(
                  initialValue: _categoriaFiltroId,
                  decoration: const InputDecoration(
                    labelText: 'Categoria (só pra filtrar sugestões, opcional)',
                  ),
                  items: categorias
                      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _categoriaFiltroId = v),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: suggestions
                      .map(
                        (s) => ActionChip(
                          label: Text(s.name),
                          onPressed: () => setState(() => _nomeController.text = s.name),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _nomeController,
                decoration: const InputDecoration(labelText: 'Nome da Ação'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe um nome' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                onPressed: _escolherDataHora,
                child: Text(
                  _dataHora == null
                      ? 'Escolher data e hora'
                      : DateFormat('dd/MM/yyyy HH:mm').format(_dataHora!),
                ),
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
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dupla Missionária'),
                subtitle: const Text('Visita com regra de composição por gênero, 2 vagas fixas'),
                value: _isMissionaryPair,
                onChanged: (v) => setState(() => _isMissionaryPair = v),
              ),
              if (_isMissionaryPair)
                DropdownButtonFormField<VisitedGender>(
                  initialValue: _visitedGender,
                  decoration: const InputDecoration(labelText: 'Gênero da pessoa visitada'),
                  items: const [
                    DropdownMenuItem(value: VisitedGender.male, child: Text('Homem')),
                    DropdownMenuItem(value: VisitedGender.female, child: Text('Mulher')),
                  ],
                  onChanged: (v) => setState(() => _visitedGender = v),
                )
              else
                TextFormField(
                  controller: _limiteVagasController,
                  decoration: const InputDecoration(
                    labelText: 'Limite de vagas (opcional)',
                    helperText: 'Deixe em branco pra vagas ilimitadas',
                  ),
                  keyboardType: TextInputType.number,
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
                    : const Text('Criar Ação'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
