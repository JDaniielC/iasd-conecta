import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../suggested_action/suggested_action_providers.dart';
import '../domain/action.dart';
import '../voting_round_providers.dart';

/// Propor Ação candidata numa Rodada de votação (User Story 1) — mesmos
/// campos de uma Ação avulsa; `grupo_id` é derivado da Rodada no banco.
class CreateCandidatePage extends ConsumerStatefulWidget {
  const CreateCandidatePage({super.key, required this.votingRoundId});

  final String votingRoundId;

  @override
  ConsumerState<CreateCandidatePage> createState() => _CreateCandidatePageState();
}

class _CreateCandidatePageState extends ConsumerState<CreateCandidatePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _detailsController = TextEditingController();
  final _capacityController = TextEditingController();
  DateTime? _dateTime;
  bool _submitting = false;
  String? _erro;
  bool _isMissionaryPair = false;
  VisitedGender? _visitedGender;

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

  NewAction? get _currentCandidate {
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

  Future<void> _propor() async {
    final candidate = _currentCandidate;
    if (_formKey.currentState?.validate() != true ||
        candidate == null ||
        !candidate.isReadyToSubmit) {
      setState(() => _erro = 'Preencha nome, data/hora e local.');
      return;
    }
    setState(() {
      _submitting = true;
      _erro = null;
    });
    try {
      await ref.read(votingRoundRepositoryProvider).proposeCandidate(widget.votingRoundId, candidate);
      ref.invalidate(candidatesProvider(widget.votingRoundId));
      if (mounted) context.pop();
    } catch (_) {
      setState(() => _erro = 'Não deu pra propor agora. A Rodada ainda está aberta?');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rodadaAsync = ref.watch(votingRoundProvider(widget.votingRoundId));
    final groupId = rodadaAsync.value?.groupId;
    final suggestionsAsync =
        groupId == null ? null : ref.watch(suggestionsForGroupProvider(groupId));
    final suggestions = suggestionsAsync?.value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Propor Ação Candidata')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (suggestions.isNotEmpty) ...[
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
                const SizedBox(height: AppSpacing.md),
              ],
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nome da candidata'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe um nome' : null,
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
                  decoration: const InputDecoration(labelText: 'Limite de vagas (opcional)'),
                  keyboardType: TextInputType.number,
                ),
              if (_erro != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: _submitting ? null : _propor,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Propor Candidata'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
