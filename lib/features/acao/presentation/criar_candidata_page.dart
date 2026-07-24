import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/acao.dart';
import '../rodada_providers.dart';

/// Propor Ação candidata numa Rodada de votação (User Story 1) — mesmos
/// campos de uma Ação avulsa; `grupo_id` é derivado da Rodada no banco.
class CriarCandidataPage extends ConsumerStatefulWidget {
  const CriarCandidataPage({super.key, required this.rodadaId});

  final String rodadaId;

  @override
  ConsumerState<CriarCandidataPage> createState() => _CriarCandidataPageState();
}

class _CriarCandidataPageState extends ConsumerState<CriarCandidataPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _localController = TextEditingController();
  final _detalhesController = TextEditingController();
  final _limiteVagasController = TextEditingController();
  DateTime? _dataHora;
  bool _enviando = false;
  String? _erro;

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

  NovaAcao? get _candidataAtual {
    if (_dataHora == null) return null;
    return NovaAcao(
      nome: _nomeController.text,
      dataHora: _dataHora!,
      local: _localController.text,
      detalhes: _detalhesController.text,
      limiteVagas: int.tryParse(_limiteVagasController.text),
    );
  }

  Future<void> _propor() async {
    final candidata = _candidataAtual;
    if (_formKey.currentState?.validate() != true ||
        candidata == null ||
        !candidata.prontoParaEnviar) {
      setState(() => _erro = 'Preencha nome, data/hora e local.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await ref.read(rodadaRepositoryProvider).proporCandidata(widget.rodadaId, candidata);
      ref.invalidate(candidatasProvider(widget.rodadaId));
      if (mounted) context.pop();
    } catch (_) {
      setState(() => _erro = 'Não deu pra propor agora. A Rodada ainda está aberta?');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Propor Ação Candidata')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nomeController,
                decoration: const InputDecoration(labelText: 'Nome da candidata'),
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
              TextFormField(
                controller: _limiteVagasController,
                decoration: const InputDecoration(labelText: 'Limite de vagas (opcional)'),
                keyboardType: TextInputType.number,
              ),
              if (_erro != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: _enviando ? null : _propor,
                child: _enviando
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
