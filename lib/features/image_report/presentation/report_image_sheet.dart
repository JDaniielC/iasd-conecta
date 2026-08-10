import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../image_report_providers.dart';

/// Denunciar uma imagem, **sem exigir cadastro** (FR-015).
///
/// Não usa `PerfilGuard.exigirPerfil`, e a ausência é deliberada: exigir
/// cadastro de quem quer retirar a foto de um filho é o oposto do Princípio II
/// (research D-006). Quem denuncia sem sessão gera denúncia sem autor, e isso
/// é aceito — a spec decidiu não criar punição nem bloqueio automático, porque
/// para um distrito de 15+ igrejas o volume não justifica maquinaria antiabuso.
class ReportImageSheet extends ConsumerStatefulWidget {
  const ReportImageSheet({super.key, required this.photoId});

  final String photoId;

  static Future<void> show(BuildContext context, {required String photoId}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: ReportImageSheet(photoId: photoId),
      ),
    );
  }

  @override
  ConsumerState<ReportImageSheet> createState() => _ReportImageSheetState();
}

class _ReportImageSheetState extends ConsumerState<ReportImageSheet> {
  final _reason = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Escreva em uma frase o que há de errado.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(imageReportRepositoryProvider)
          .report(photoId: widget.photoId, reason: reason);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Recebemos. O Administrador do distrito vai avaliar a imagem.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _error = 'Não deu pra enviar agora. Verifique sua conexão e tente de novo.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Denunciar esta imagem', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text(
              'Você não precisa ter cadastro para denunciar. Se aparece uma '
              'criança ou adolescente nesta imagem, diga isso — é o motivo '
              'que a gente trata primeiro.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              maxLines: 3,
              maxLength: 300,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'O que há de errado?',
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _sending ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _sending ? null : _send,
                    child: const Text('Enviar denúncia'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
