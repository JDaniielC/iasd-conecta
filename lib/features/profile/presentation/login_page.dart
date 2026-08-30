import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/login_error.dart';

/// Login em outro aparelho (User Story 3): só funciona pra quem já fez
/// upgrade pra Conta — Perfil sozinho não é recuperável entre aparelhos
/// (ver contracts/auth-flow.md).
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).login(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      ref.invalidate(hasProfileProvider);
      // Navegação explícita, não só invalidar e esperar o redirect global de
      // app.dart: aquele redirect só reavalia quando hasProfileProvider MUDA
      // de valor. Uma Conta que já tinha Perfil antes de logar (recuperando
      // sessão num aparelho novo — o próprio caso desta tela) faz o valor
      // ficar igual antes e depois, o redirect nunca reavalia, e a pessoa
      // fica presa aqui. Ver test/widget/login_page_test.dart.
      if (mounted) context.go('/home');
    } catch (error) {
      // `catch` sem tipo de propósito: `on AuthException` deixava passar
      // falha de rede e de servidor, que subiam sem ninguém capturar — o
      // botão voltava ao normal e a tela não dizia nada. Qual frase cabe a
      // cada falha é decidido por `loginErrorMessage`, que é onde FR-014
      // está escrito e testado.
      setState(() => _error = loginErrorMessage(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'E-mail'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Senha'),
                obscureText: true,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: _submitting ? null : _signIn,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Entrar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
