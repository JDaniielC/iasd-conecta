import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
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
  String? _error;
  bool _isMissionaryPair = false;
  VisitedGender? _visitedGender;
  bool _restrictedToGroup = false;

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
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    setState(() {
      _dateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  NewAction? get _currentCandidate {
    if (_dateTime == null) return null;
    return NewAction(
      name: _nameController.text,
      dateTime: _dateTime!,
      location: _locationController.text,
      details: _detailsController.text,
      capacity: int.tryParse(_capacityController.text),
      isMissionaryPair: _isMissionaryPair,
      visitedGender: _visitedGender,
      restrictedToGroup: _restrictedToGroup,
    );
  }

  Future<void> _propose() async {
    final candidate = _currentCandidate;
    if (_formKey.currentState?.validate() != true ||
        candidate == null ||
        !candidate.isReadyToSubmit) {
      setState(() => _error = 'Preencha nome, data/hora e local.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(votingRoundRepositoryProvider).proposeCandidate(widget.votingRoundId, candidate);
      ref.invalidate(candidatesProvider(widget.votingRoundId));
      if (mounted) context.pop();
    } catch (_) {
      setState(() => _error = 'Não deu pra propor agora. A Rodada ainda está aberta?');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final creatorDisplayName = _watchCreatorDisplayName(ref);
    final votingRoundAsync = ref.watch(votingRoundProvider(widget.votingRoundId));
    final groupId = votingRoundAsync.value?.groupId;
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
                decoration: const InputDecoration(
                  labelText: 'Nome da candidata',
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
                  decoration: const InputDecoration(labelText: 'Limite de vagas (opcional)'),
                  keyboardType: TextInputType.number,
                ),
              // Change `acao-direcionada-a-grupo`. O controle vive AQUI, e não
              // em `create_action_page.dart`: Ação de Grupo neste app só nasce
              // como candidata de Rodada (`acoes_candidata_checar_regras`), e
              // na tela de Ação avulsa não haveria Grupo a que se referir.
              // A vencedora da Rodada herda de graça — é a mesma linha.
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Só para quem participa do Grupo'),
                subtitle: const Text(
                  'A Ação não aparece para quem não participa deste Grupo, '
                  'nem para quem está sem login. A lista de quem vai também fica '
                  'escondida.',
                ),
                value: _restrictedToGroup,
                onChanged: (v) => setState(() => _restrictedToGroup = v),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: _submitting ? null : _propose,
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
