import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../acao_providers.dart';
import '../domain/acao.dart';

/// Criação de Ação avulsa (User Story 1). Já nasce confirmada, sem
/// votação; o criador vira confirmado automaticamente (trigger no banco).
class CriarAcaoPage extends ConsumerStatefulWidget {
  const CriarAcaoPage({super.key});

  @override
  ConsumerState<CriarAcaoPage> createState() => _CriarAcaoPageState();
}

class _CriarAcaoPageState extends ConsumerState<CriarAcaoPage> {
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

  NovaAcao? get _acaoAtual {
    if (_dataHora == null) return null;
    return NovaAcao(
      nome: _nomeController.text,
      dataHora: _dataHora!,
      local: _localController.text,
      detalhes: _detalhesController.text,
      limiteVagas: int.tryParse(_limiteVagasController.text),
      isMissionaryPair: _isMissionaryPair,
      visitedGender: _visitedGender,
    );
  }

  Future<void> _criar() async {
    final acao = _acaoAtual;
    if (_formKey.currentState?.validate() != true || acao == null || !acao.prontoParaEnviar) {
      setState(() => _erro = 'Preencha nome, data/hora e local.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await ref.read(acaoRepositoryProvider).criarAcao(acao);
      ref.invalidate(acoesProvider);
      if (mounted) context.pop();
    } catch (_) {
      setState(() => _erro = 'Não deu pra criar a Ação agora. Tente de novo.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Criar Ação')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
