import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/rodada.dart';
import '../rodada_providers.dart';

/// Abertura de Rodada de votação (User Story 1) — só o prazo é informado;
/// quem participa do Grupo já é garantido pelo trigger no banco.
class CriarRodadaPage extends ConsumerStatefulWidget {
  const CriarRodadaPage({super.key, required this.grupoId});

  final String grupoId;

  @override
  ConsumerState<CriarRodadaPage> createState() => _CriarRodadaPageState();
}

class _CriarRodadaPageState extends ConsumerState<CriarRodadaPage> {
  DateTime? _prazo;
  bool _enviando = false;
  String? _erro;

  Future<void> _escolherPrazo() async {
    final agora = DateTime.now();
    final data = await showDatePicker(
      context: context,
      initialDate: agora.add(const Duration(days: 1)),
      firstDate: agora,
      lastDate: agora.add(const Duration(days: 365)),
    );
    if (data == null || !mounted) return;
    final hora = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (hora == null) return;
    setState(() {
      _prazo = DateTime(data.year, data.month, data.day, hora.hour, hora.minute);
    });
  }

  Future<void> _abrir() async {
    final prazo = _prazo;
    if (prazo == null) {
      setState(() => _erro = 'Escolha um prazo.');
      return;
    }
    final rodada = NovaRodada(prazo: prazo);
    if (!rodada.prontoParaEnviar) {
      setState(() => _erro = 'O prazo precisa ser no futuro.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await ref.read(rodadaRepositoryProvider).abrirRodada(rodada, grupoId: widget.grupoId);
      ref.invalidate(rodadasDoGrupoProvider(widget.grupoId));
      if (mounted) context.pop();
    } catch (_) {
      setState(() => _erro = 'Não deu pra abrir a Rodada agora. Você participa deste Grupo?');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Abrir Rodada de Votação')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Escolha até quando a votação fica aberta.'),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: _escolherPrazo,
              child: Text(
                _prazo == null
                    ? 'Escolher prazo'
                    : DateFormat('dd/MM/yyyy HH:mm').format(_prazo!),
              ),
            ),
            if (_erro != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: _enviando ? null : _abrir,
              child: _enviando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Abrir Rodada'),
            ),
          ],
        ),
      ),
    );
  }
}
