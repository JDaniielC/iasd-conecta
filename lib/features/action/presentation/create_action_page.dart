import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
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
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _detailsController = TextEditingController();
  final _capacityController = TextEditingController();
  DateTime? _dateTime;
  bool _submitting = false;
  String? _error;
  bool _isMissionaryPair = false;
  VisitedGender? _visitedGender;
  String? _categoryFilterId;

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _detailsController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final data = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (data == null || !mounted) return;
    final hora = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (hora == null) return;
    setState(() {
      _dateTime = DateTime(data.year, data.month, data.day, hora.hour, hora.minute);
    });
  }

  NewAction? get _currentAction {
    if (_dateTime == null) return null;
    return NewAction(
      name: _nameController.text,
      dateTime: _dateTime!,
      local: _locationController.text,
      details: _detailsController.text,
      capacity: int.tryParse(_capacityController.text),
      isMissionaryPair: _isMissionaryPair,
      visitedGender: _visitedGender,
    );
  }

  Future<void> _submit() async {
    final action = _currentAction;
    if (_formKey.currentState?.validate() != true || action == null || !action.isReadyToSubmit) {
      setState(() => _error = 'Preencha nome, data/hora e local.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(actionRepositoryProvider).createAction(action);
      ref.invalidate(actionsProvider);
      if (mounted) context.pop();
    } catch (_) {
      setState(() => _error = 'Não deu pra criar a Ação agora. Tente de novo.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final creatorDisplayName = _watchCreatorDisplayName(ref);
    final categoriesAsync = ref.watch(groupCategoriesProvider);
    final suggestionsAsync = _categoryFilterId == null
        ? null
        : ref.watch(suggestionsForCategoryProvider(_categoryFilterId!));
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
              categoriesAsync.when(
                data: (categories) => DropdownButtonFormField<String>(
                  initialValue: _categoryFilterId,
                  decoration: const InputDecoration(
                    labelText: 'Categoria (só pra filtrar sugestões, opcional)',
                  ),
                  items: categories
                      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _categoryFilterId = v),
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
                          onPressed: () => setState(() => _nameController.text = s.name),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nome da Ação',
                  helperText: 'O nome descreve a atividade, não a pessoa. '
                      'Ex.: Visita a afastado, Ensaio, Culto Jovem',
                  helperMaxLines: 3,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Informe um nome';
                  // FR-017: recusa o nome da própria pessoa que está criando.
                  // É igualdade, não `contains` — "Visita a José" é legítimo.
                  if (isCreatorOwnName(v, creatorDisplayName)) {
                    return 'O nome da Ação descreve a atividade, não a pessoa. '
                        'Ex.: Visita a afastado';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                onPressed: _pickDateTime,
                child: Text(
                  _dateTime == null
                      ? 'Escolher data e hora'
                      : DateFormat('dd/MM/yyyy HH:mm').format(_dateTime!),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(labelText: 'Local'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o local' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _detailsController,
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
                  controller: _capacityController,
                  decoration: const InputDecoration(
                    labelText: 'Limite de vagas (opcional)',
                    helperText: 'Deixe em branco pra vagas ilimitadas',
                  ),
                  keyboardType: TextInputType.number,
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
                    : const Text('Criar Ação'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nome de exibição de quem está criando, para a recusa de FR-017.
///
/// Vem da RPC `perfil_publico` (via [publicProfileProvider]), nunca de um
/// `select` direto em `perfis` — é ela que devolve o Apelido no lugar do nome
/// real quando o Usuário é menor de idade, e FR-017 pede que o Apelido também
/// seja recusado.
///
/// Devolve `null` quando não há sessão ou a RPC ainda não respondeu: nesse
/// caso a validação não bloqueia (research D-005).
String? _watchCreatorDisplayName(WidgetRef ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;
  // `watch`, não `read`: o provider é preguiçoso, e um `read` no validador
  // devolveria null porque ninguém o teria observado antes.
  return ref.watch(publicProfileProvider(uid)).value?.displayName;
}
