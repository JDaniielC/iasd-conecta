import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/name_moderation.dart';
import '../domain/profile_error_message.dart';
import '../domain/profile.dart';

/// Formulário de criação de Perfil (User Story 1) com etapa condicional de
/// Apelido para menores de idade (User Story 2, FR-005).
///
/// Sem campo de e-mail/senha — Perfil não exige credencial (FR-001).
class ProfileSignupPage extends ConsumerStatefulWidget {
  const ProfileSignupPage({super.key});

  @override
  ConsumerState<ProfileSignupPage> createState() =>
      _ProfileSignupPageState();
}

class _ProfileSignupPageState extends ConsumerState<ProfileSignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ageController = TextEditingController();

  Gender _gender = Gender.female;
  String? _churchId;
  bool _lgpdConsent = false;
  bool _churchConsent = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Profile? get _currentProfile {
    final age = int.tryParse(_ageController.text);
    if (age == null) return null;
    return Profile(
      name: _nameController.text,
      gender: _gender,
      age: age,
      lgpdConsentAccepted: _lgpdConsent,
      nickname: _nicknameController.text,
      churchId: _churchId,
      phone: _phoneController.text,
      churchLgpdConsentAccepted: _churchConsent,
    );
  }

  Future<void> _enviar() async {
    final profile = _currentProfile;
    if (_formKey.currentState?.validate() != true || profile == null) return;
    if (!NameModeration.cached.isValid(profile.name)) {
      setState(() => _error = 'Esse nome não pode ser usado. Tente outro.');
      return;
    }
    if (!profile.readyToSubmit) {
      setState(() => _error = 'Revise o formulário antes de continuar.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).createProfile(profile);
      ref.invalidate(hasProfileProvider);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        // Chave primária de perfis é o uid — duplicidade só pode significar
        // que uma tentativa anterior já criou o Perfil (ex.: resposta se
        // perdeu por timeout de rede, mas o insert chegou no banco). Não é
        // erro do usuário: só seguir em frente, senão ele fica preso
        // tentando de novo pra sempre.
        ref.invalidate(hasProfileProvider);
      } else {
        setState(() => _error = profileErrorMessage(e, fallback: 'Não deu pra concluir o cadastro agora. Tente de novo.'));
      }
    } catch (_) {
      setState(() => _error =
          'Não deu pra concluir o cadastro agora. Verifique sua conexão e tente de novo.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final churchesAsync = ref.watch(churchesProvider);
    final age = int.tryParse(_ageController.text);
    final needsNickname = age != null && age < 18;

    return Scaffold(
      appBar: AppBar(title: const Text('Criar Perfil')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Sem e-mail, sem senha — só o essencial pra participar.',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nome'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe seu nome' : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<Gender>(
                initialValue: _gender,
                decoration: const InputDecoration(labelText: 'Gênero'),
                items: Gender.values
                    .map((g) => DropdownMenuItem(
                          value: g,
                          child: Text(g == Gender.male ? 'Masculino' : 'Feminino'),
                        ))
                    .toList(),
                onChanged: (g) => setState(() => _gender = g ?? _gender),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _ageController,
                decoration: const InputDecoration(labelText: 'Idade'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 0) return 'Informe uma idade válida';
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              churchesAsync.when(
                data: (churches) => DropdownButtonFormField<String>(
                  initialValue: _churchId,
                  decoration:
                      const InputDecoration(labelText: 'Igreja de origem (opcional)'),
                  items: churches
                      .map((c) =>
                          DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (id) => setState(() {
                    _churchId = id;
                    // Trocar ou remover a igreja invalida o consentimento
                    // anterior — força reafirmar (LGPD art. 11 I).
                    _churchConsent = false;
                  }),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const Text('Não deu pra carregar as igrejas agora.'),
              ),
              if (_churchId != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.primary),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: CheckboxListTile(
                    value: _churchConsent,
                    onChanged: (v) => setState(() => _churchConsent = v ?? false),
                    title: const Text(
                      'Autorizo o uso da minha igreja de origem para destacar '
                      'Grupos e Ações dela para mim (dado sensível — LGPD art. 11, I).',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _phoneController,
                decoration:
                    const InputDecoration(labelText: 'Telefone (opcional)'),
                keyboardType: TextInputType.phone,
              ),
              if (needsNickname) ...[
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _nicknameController,
                  decoration: const InputDecoration(
                    labelText: 'Apelido (obrigatório para menores de 18)',
                    helperText:
                        'Sem informação identificável — aparece no lugar do seu nome real',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Apelido é obrigatório para menores de idade'
                      : null,
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => context.push('/privacidade'),
                      child: const Text('Política de Privacidade'),
                    ),
                    TextButton(
                      onPressed: () => context.push('/termos'),
                      child: const Text('Termos de Uso'),
                    ),
                  ],
                ),
              ),
              CheckboxListTile(
                value: _lgpdConsent,
                onChanged: (v) => setState(() => _lgpdConsent = v ?? false),
                title: const Text(
                  'Li e aceito o uso dos meus dados descrito na Política de '
                  'Privacidade (LGPD)',
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: (_submitting || _currentProfile?.readyToSubmit != true)
                    ? null
                    : _enviar,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Concluir cadastro'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => context.push('/login'),
                child: const Text('Já tenho Conta em outro aparelho'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
