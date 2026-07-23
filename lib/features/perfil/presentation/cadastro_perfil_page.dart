import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/nome_moderation.dart';
import '../domain/perfil.dart';

/// Formulário de criação de Perfil (User Story 1) com etapa condicional de
/// Apelido para menores de idade (User Story 2, FR-005).
///
/// Sem campo de e-mail/senha — Perfil não exige credencial (FR-001).
class CadastroPerfilPage extends ConsumerStatefulWidget {
  const CadastroPerfilPage({super.key});

  @override
  ConsumerState<CadastroPerfilPage> createState() =>
      _CadastroPerfilPageState();
}

class _CadastroPerfilPageState extends ConsumerState<CadastroPerfilPage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeController = TextEditingController();
  final _apelidoController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _idadeController = TextEditingController();

  // Cache local mínima — a checagem que vale é a constraint no banco.
  final _moderacao = const NomeModeration(['idiota', 'burro', 'estupido', 'imbecil', 'babaca']);

  Genero _genero = Genero.feminino;
  String? _igrejaId;
  bool _consentimentoLgpd = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _nomeController.dispose();
    _apelidoController.dispose();
    _telefoneController.dispose();
    _idadeController.dispose();
    super.dispose();
  }

  Perfil? get _perfilAtual {
    final idade = int.tryParse(_idadeController.text);
    if (idade == null) return null;
    return Perfil(
      nome: _nomeController.text,
      genero: _genero,
      idade: idade,
      consentimentoLgpdAceito: _consentimentoLgpd,
      apelido: _apelidoController.text,
      igrejaId: _igrejaId,
      telefone: _telefoneController.text,
    );
  }

  Future<void> _enviar() async {
    final perfil = _perfilAtual;
    if (_formKey.currentState?.validate() != true || perfil == null) return;
    if (!_moderacao.valido(perfil.nome)) {
      setState(() => _erro = 'Esse nome não pode ser usado. Tente outro.');
      return;
    }
    if (!perfil.prontoParaEnviar) {
      setState(() => _erro = 'Revise o formulário antes de continuar.');
      return;
    }

    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await ref.read(perfilRepositoryProvider).criarPerfil(perfil);
      ref.invalidate(hasPerfilProvider);
    } on PostgrestException catch (e) {
      setState(() => _erro = _mensagemDeErro(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  String _mensagemDeErro(PostgrestException e) {
    if (e.message.contains('nome_valido')) {
      return 'Esse nome não pode ser usado. Tente outro.';
    }
    if (e.message.contains('apelido_obrigatorio_menor')) {
      return 'Menores de idade precisam definir um Apelido.';
    }
    return 'Não deu pra concluir o cadastro agora. Tente de novo.';
  }

  @override
  Widget build(BuildContext context) {
    final igrejasAsync = ref.watch(igrejasProvider);
    final idade = int.tryParse(_idadeController.text);
    final precisaApelido = idade != null && idade < 18;

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
                controller: _nomeController,
                decoration: const InputDecoration(labelText: 'Nome'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Informe seu nome' : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<Genero>(
                initialValue: _genero,
                decoration: const InputDecoration(labelText: 'Gênero'),
                items: Genero.values
                    .map((g) => DropdownMenuItem(
                          value: g,
                          child: Text(g == Genero.masculino ? 'Masculino' : 'Feminino'),
                        ))
                    .toList(),
                onChanged: (g) => setState(() => _genero = g ?? _genero),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _idadeController,
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
              igrejasAsync.when(
                data: (igrejas) => DropdownButtonFormField<String>(
                  initialValue: _igrejaId,
                  decoration:
                      const InputDecoration(labelText: 'Igreja de origem (opcional)'),
                  items: igrejas
                      .map((i) =>
                          DropdownMenuItem(value: i.id, child: Text(i.nome)))
                      .toList(),
                  onChanged: (id) => setState(() => _igrejaId = id),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const Text('Não deu pra carregar as igrejas agora.'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _telefoneController,
                decoration:
                    const InputDecoration(labelText: 'Telefone (opcional)'),
                keyboardType: TextInputType.phone,
              ),
              if (precisaApelido) ...[
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _apelidoController,
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
              CheckboxListTile(
                value: _consentimentoLgpd,
                onChanged: (v) => setState(() => _consentimentoLgpd = v ?? false),
                title: const Text('Aceito o uso dos meus dados (LGPD)'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_erro != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: (_enviando || _perfilAtual?.prontoParaEnviar != true)
                    ? null
                    : _enviar,
                child: _enviando
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
