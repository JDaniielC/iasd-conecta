import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';

/// Exclusão de conta (feature 009 — LGPD art. 18, VI).
///
/// A tela existe para que a pessoa saiba exatamente o que acontece antes de
/// confirmar: o que é apagado, o que permanece como registro de eventos que
/// envolveram outras pessoas, e que não há volta (FR-002).
class DeleteAccountPage extends ConsumerStatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  ConsumerState<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends ConsumerState<DeleteAccountPage> {
  bool _understood = false;
  bool _submitting = false;
  String? _error;

  Future<void> _delete() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).deleteMyAccount();
      ref.invalidate(hasProfileProvider);
    } catch (e) {
      setState(() => _error = _errorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// As recusas de `excluir_minha_conta()` são regra de negócio e precisam
  /// chegar ao Usuário: elas dizem o que fazer antes de tentar de novo. Só o
  /// que não é recusa vira mensagem genérica — erro de banco cru não é texto
  /// de UI.
  String _errorMessage(Object error) {
    if (error is PostgrestException) {
      final message = error.message;
      if (message.contains('Dono de Grupo') ||
          message.contains('Administrador do distrito')) {
        return message;
      }
    }
    return 'Não deu pra concluir a exclusão agora. Verifique sua conexão e '
        'tente de novo.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Excluir conta')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'O que é apagado',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Seu nome, Apelido, telefone, Igreja de origem, gênero e idade. '
              'Seu acesso é encerrado na hora e você não consegue mais entrar. '
              'Você também sai dos Grupos de que participa e deixa de ocupar '
              'vaga em Ações que ainda vão acontecer — se houver fila de '
              'espera, a próxima pessoa assume seu lugar.',
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'O que permanece',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'O registro das Ações que já aconteceram, incluindo sua presença '
              'nelas, continua existindo — ele conta a história de outras '
              'pessoas também. Nesses registros você aparece como '
              '"Membro removido", sem nada que identifique quem era.',
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Não tem volta. Se um dia quiser voltar, será um cadastro novo, '
              'sem ligação com este.',
            ),
            const SizedBox(height: AppSpacing.lg),
            CheckboxListTile(
              value: _understood,
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _understood = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('Entendi que a exclusão é definitiva'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: (_understood && !_submitting) ? _delete : null,
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: Text(_submitting ? 'Excluindo…' : 'Excluir minha conta'),
            ),
          ],
        ),
      ),
    );
  }
}
