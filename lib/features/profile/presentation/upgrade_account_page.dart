import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';

/// Upgrade opcional de Perfil para Conta (User Story 3, FR-011).
///
/// Sempre cancelável — nunca é pré-requisito pra nada coberto por esta
/// feature, só pra persistir entre aparelhos e pra declarar Líder/Diretor
/// no futuro (FR-012).
class UpgradeAccountPage extends ConsumerStatefulWidget {
  const UpgradeAccountPage({super.key});

  @override
  ConsumerState<UpgradeAccountPage> createState() => _UpgradeAccountPageState();
}

class _UpgradeAccountPageState extends ConsumerState<UpgradeAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await ref.read(authRepositoryProvider).upgradeToAccount(
            email: _emailController.text.trim(),
            senha: _senhaController.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (_) {
      // Mensagem genérica: nunca revela se o e-mail já tem Conta
      // (mesmo cuidado do login_page.dart, FR-014 da feature 001).
      setState(() => _erro = 'Não deu pra virar Conta com esses dados. Tente de novo.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Virar Conta')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Vincule um e-mail e senha pra recuperar seu Perfil em outro '
                'aparelho. Isso é opcional — você pode cancelar a qualquer '
                'momento sem perder nada do que já cadastrou.',
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'E-mail'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) =>
                    (v == null || !v.contains('@')) ? 'E-mail inválido' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _senhaController,
                decoration: const InputDecoration(labelText: 'Senha'),
                obscureText: true,
                validator: (v) => (v == null || v.length < 6)
                    ? 'Senha precisa de ao menos 6 caracteres'
                    : null,
              ),
              if (_erro != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: _enviando ? null : _confirmar,
                child: _enviando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Confirmar upgrade'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
