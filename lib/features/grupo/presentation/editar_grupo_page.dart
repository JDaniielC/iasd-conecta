import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../grupo_providers.dart';

/// Administração do Grupo pelo Dono (User Story 3): editar campos, remover
/// participante, transferir posse. RLS + triggers no banco são a garantia
/// real (FR-009/010/011/012); esta tela é só a UI sobre isso.
class EditarGrupoPage extends ConsumerStatefulWidget {
  const EditarGrupoPage({super.key, required this.grupoId});

  final String grupoId;

  @override
  ConsumerState<EditarGrupoPage> createState() => _EditarGrupoPageState();
}

class _EditarGrupoPageState extends ConsumerState<EditarGrupoPage> {
  final _nomeController = TextEditingController();
  final _detalhesController = TextEditingController();
  bool _carregouCampos = false;
  String? _erro;

  @override
  void dispose() {
    _nomeController.dispose();
    _detalhesController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    try {
      await ref.read(grupoRepositoryProvider).editarGrupo(
            widget.grupoId,
            nome: _nomeController.text,
            detalhes: _detalhesController.text,
          );
      ref.invalidate(grupoProvider(widget.grupoId));
      ref.invalidate(gruposProvider);
      if (mounted) context.pop();
    } catch (_) {
      setState(() => _erro = 'Não deu pra salvar. Você ainda é o Dono deste Grupo?');
    }
  }

  Future<void> _removerParticipante(String usuarioId) async {
    try {
      await ref.read(grupoRepositoryProvider).removerParticipante(widget.grupoId, usuarioId);
      ref.invalidate(participantesProvider(widget.grupoId));
    } catch (_) {
      setState(() => _erro = 'Não deu pra remover esse participante.');
    }
  }

  Future<void> _transferirPosse(String novoDonoId) async {
    try {
      await ref.read(grupoRepositoryProvider).transferirPosse(widget.grupoId, novoDonoId);
      ref.invalidate(grupoProvider(widget.grupoId));
      if (mounted) context.pop();
    } catch (_) {
      setState(() => _erro = 'Não deu pra transferir a posse.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final grupoAsync = ref.watch(grupoProvider(widget.grupoId));
    final participantesAsync = ref.watch(participantesProvider(widget.grupoId));
    final uid = ref.watch(currentUserIdProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Editar Grupo')),
      body: grupoAsync.when(
        data: (grupo) {
          if (!grupo.souDono(uid)) {
            return const Center(child: Text('Você não é o Dono deste Grupo.'));
          }
          if (!_carregouCampos) {
            _nomeController.text = grupo.nome;
            _detalhesController.text = grupo.detalhes ?? '';
            _carregouCampos = true;
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nomeController,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _detalhesController,
                  decoration: const InputDecoration(labelText: 'Detalhes'),
                  maxLines: 3,
                ),
                if (_erro != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: AppSpacing.lg),
                ElevatedButton(onPressed: _salvar, child: const Text('Salvar')),
                const SizedBox(height: AppSpacing.lg),
                Text('Participantes', style: Theme.of(context).textTheme.titleLarge),
                participantesAsync.when(
                  data: (participantes) => Column(
                    children: participantes.map((p) {
                      final ehODono = p.id == grupo.donoId;
                      return ListTile(
                        title: Text(p.nomeExibido),
                        subtitle: ehODono ? const Text('Dono') : null,
                        trailing: ehODono
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: () => _transferirPosse(p.id),
                                    child: const Text('Tornar Dono'),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.person_remove_outlined),
                                    onPressed: () => _removerParticipante(p.id),
                                  ),
                                ],
                              ),
                      );
                    }).toList(),
                  ),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const Text('Não deu pra carregar os participantes.'),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Grupo não encontrado.')),
      ),
    );
  }
}
