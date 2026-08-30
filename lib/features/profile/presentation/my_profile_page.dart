import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../chat/chat_providers.dart';
import '../../chat/domain/pinned_message.dart';
import '../domain/name_moderation.dart';
import '../domain/profile.dart';
import '../domain/profile_error_message.dart';

/// Meu Perfil — ver e corrigir os próprios dados (LGPD art. 18, II e III).
///
/// Até esta tela existir, o titular dependia de e-mail para conferir o próprio
/// nome, e a Política de Privacidade dizia isso com todas as letras. A
/// permissão de escrita (`perfis_update_own`) estava no banco desde o começo e
/// nenhuma linha de código a usava.
///
/// **Idade e gênero são exibidos, não editáveis.** Os dois decidem regra de
/// domínio — idade decide se o Apelido é obrigatório, gênero valida a
/// composição de Dupla Missionária — e mudá-los tem consequência que esta
/// feature não carrega. Continuam sendo corrigidos por e-mail, e a Política
/// diz isso.
class MyProfilePage extends ConsumerStatefulWidget {
  const MyProfilePage({super.key});

  @override
  ConsumerState<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends ConsumerState<MyProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _phoneController = TextEditingController();

  /// Preenchido uma vez, quando o Perfil chega do banco. Sem isto, cada
  /// rebuild jogaria fora o que a pessoa está digitando.
  bool _initialized = false;

  String? _churchId;
  bool _churchConsent = false;
  bool _submitting = false;
  String? _error;

  /// A Igreja e a data que vieram do banco. Guardadas para decidir se o
  /// consentimento é novo (recarimba) ou o mesmo (preserva a data original).
  String? _originalChurchId;
  DateTime? _originalChurchConsentAt;

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _initializeFrom(Profile profile) {
    if (_initialized) return;
    _initialized = true;
    _nameController.text = profile.name;
    _nicknameController.text = profile.nickname ?? '';
    _phoneController.text = profile.phone ?? '';
    _churchId = profile.churchId;
    _originalChurchId = profile.churchId;
    _originalChurchConsentAt = profile.churchLgpdConsentAcceptedAt;
    // Igreja que já estava lá já foi consentida — não se pede de novo.
    _churchConsent = profile.churchId != null;
  }

  /// Monta o Profile a partir do formulário, preservando o que não é editável.
  Profile _formProfile(Profile loaded) {
    final churchChanged = _churchId != _originalChurchId;
    return Profile(
      name: _nameController.text,
      gender: loaded.gender,
      age: loaded.age,
      lgpdConsentAccepted: true,
      nickname: _nicknameController.text,
      churchId: _churchId,
      phone: _phoneController.text,
      churchLgpdConsentAccepted: _churchConsent,
      lgpdConsentAcceptedAt: loaded.lgpdConsentAcceptedAt,
      // Igreja nova ou trocada é aceite novo, e aceite novo tem data nova.
      // Igreja igual mantém a data original: recarimbar a cada correção de
      // telefone apagaria quando o consentimento foi de fato dado.
      churchLgpdConsentAcceptedAt: _churchId == null
          ? null
          : churchChanged
              ? DateTime.now().toUtc()
              : _originalChurchConsentAt ?? DateTime.now().toUtc(),
    );
  }

  Future<void> _save(Profile loaded) async {
    final profile = _formProfile(loaded);
    if (!NameModeration.cached.isValid(profile.name)) {
      setState(() => _error = 'Esse nome não pode ser usado. Tente outro.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).updateMyProfile(profile);
      if (!mounted) return;
      ref.invalidate(myProfileProvider);
      // `publicProfileProvider` é autoDispose.family e fica em cache enquanto
      // alguma tela o observa. Sem invalidar, o nome corrigido não aparece na
      // página do Grupo — e falharia sem erro e sem teste vermelho.
      ref.invalidate(publicProfileProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dados atualizados.')),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _error = profileErrorMessage(
            e,
            fallback:
                'Não deu pra salvar agora. Verifique sua conexão e tente de novo.',
          ));
    } catch (_) {
      if (!mounted) return;
      // Nada é invalidado: o banco não mudou, então o que está na tela
      // continua sendo o que está guardado.
      setState(() => _error =
          'Não deu pra salvar agora. Verifique sua conexão e tente de novo.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Meu Perfil')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Text(
              'Não deu pra carregar seus dados agora. Verifique sua conexão e '
              'tente de novo.',
            ),
          ),
        ),
        data: (profile) {
          _initializeFrom(profile);
          return _buildForm(context, profile);
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context, Profile loaded) {
    final churchesAsync = ref.watch(churchesProvider);
    final formProfile = _formProfile(loaded);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'É tudo que o app guarda sobre você.',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _nicknameController,
              decoration: InputDecoration(
                labelText: loaded.isMinor
                    ? 'Apelido (obrigatório para menores de 18)'
                    : 'Apelido',
                helperText: _nicknameController.text.trim().isEmpty
                    ? 'não informado'
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            churchesAsync.when(
              data: (churches) => DropdownButtonFormField<String>(
                initialValue: _churchId,
                decoration: InputDecoration(
                  labelText: 'Igreja de origem',
                  helperText: _churchId == null ? 'não informado' : null,
                ),
                items: [
                  const DropdownMenuItem<String>(
                    child: Text('Nenhuma'),
                  ),
                  ...churches.map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ),
                ],
                onChanged: (id) => setState(() {
                  _churchId = id;
                  // Trocar ou remover a igreja invalida o consentimento
                  // anterior — força reafirmar (LGPD art. 11 I).
                  _churchConsent = false;
                }),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, _) =>
                  const Text('Não deu pra carregar as igrejas agora.'),
            ),
            if (_churchId != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                decoration: BoxDecoration(
                  border:
                      Border.all(color: Theme.of(context).colorScheme.primary),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: CheckboxListTile(
                  value: _churchConsent,
                  onChanged: (v) =>
                      setState(() => _churchConsent = v ?? false),
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
              decoration: InputDecoration(
                labelText: 'Telefone',
                helperText: _phoneController.text.trim().isEmpty
                    ? 'não informado'
                    : null,
              ),
              keyboardType: TextInputType.phone,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.lg),
            _ReadOnlyRow(
              label: 'Gênero',
              value: switch (loaded.gender) {
                Gender.male => 'Masculino',
                Gender.female => 'Feminino',
                null => 'não informado',
              },
            ),
            _ReadOnlyRow(
              label: 'Idade',
              value: loaded.age?.toString() ?? 'não informado',
            ),
            _ReadOnlyRow(
              label: 'Consentimento aceito em',
              value: _formatDate(loaded.lgpdConsentAcceptedAt),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Gênero e idade só podem ser corrigidos por e-mail — eles decidem '
              'regras do app, como a exigência de Apelido e a composição de '
              'Dupla Missionária.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: (_submitting || !formProfile.readyToSubmit)
                  ? null
                  : () => _save(loaded),
              child: Text(_submitting ? 'Salvando…' : 'Salvar'),
            ),
            const _PinnedMessagesSection(),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return 'não informado';
    final localDate = date.toLocal();
    final day = localDate.day.toString().padLeft(2, '0');
    final month = localDate.month.toString().padLeft(2, '0');
    return '$day/$month/${localDate.year}';
  }
}

/// Change `alcance-do-titular-sobre-texto-proprio` — as próprias mensagens
/// fixadas, alcançáveis daqui mesmo sem a pessoa entrar na conversa onde
/// escreveu (PENDENCIAS.md 2.28).
///
/// **Some quando não há nenhuma**, mesma escolha da faixa de destaque em
/// `/acoes`: seção vazia declarando que não há nada é espaço gasto à toa.
class _PinnedMessagesSection extends ConsumerStatefulWidget {
  const _PinnedMessagesSection();

  @override
  ConsumerState<_PinnedMessagesSection> createState() =>
      _PinnedMessagesSectionState();
}

class _PinnedMessagesSectionState
    extends ConsumerState<_PinnedMessagesSection> {
  /// Preenchida uma vez, quando a lista chega. Depois disso ela só muda por
  /// desfixar LOCAL — nunca por um novo carregamento. É o que faz "desfixar
  /// tira a linha na hora, sem recarregar" ser verdade: recarregar reabriria
  /// a mesma ida ao servidor que a pessoa já pagou para abrir esta tela.
  List<PinnedMessage>? _messages;

  Future<void> _unpin(PinnedMessage message) async {
    try {
      await ref.read(chatRepositoryProvider).unpinMyMessage(message.id);
      if (!mounted) return;
      setState(() => _messages?.removeWhere((m) => m.id == message.id));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não deu pra desfixar agora. Tente de novo.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _messages ??= ref.watch(myPinnedMessagesProvider).value;
    final messages = _messages;
    if (messages == null || messages.isEmpty) return const SizedBox.shrink();

    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: AppSpacing.sm),
          Text('Mensagens fixadas', style: text.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'O que você fixou continua seu para desfixar, mesmo que você já '
            'não alcance mais aquela conversa.',
            style: text.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final m in messages)
            _PinnedMessageTile(message: m, onUnpin: () => _unpin(m)),
        ],
      ),
    );
  }
}

class _PinnedMessageTile extends StatelessWidget {
  const _PinnedMessageTile({required this.message, required this.onUnpin});

  final PinnedMessage message;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.spaceName, style: text.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(message.text, style: text.bodyMedium),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onUnpin,
                child: const Text('Desfixar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
