import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../cover_photo/cover_photo_providers.dart';
import '../../district_admin/district_admin_providers.dart';
import '../domain/image_report.dart';
import '../image_report_providers.dart';

/// As imagens denunciadas que esperam decisão do Administrador do distrito.
///
/// **Uma linha por imagem, não por denúncia** (FR-018): dez pessoas
/// denunciando a mesma foto são um item com contagem 10. Resolver o item
/// resolve todas. Sem isso, uma imagem que incomodou muita gente enterraria as
/// outras pendências.
///
/// O portão de acesso mora **aqui**, e não no `redirect` do roteador. É a lição
/// da feature 018: o provider de administrador é assíncrono e vale `null`
/// durante a navegação, então um `redirect` que compare `value == false` nunca
/// dispara e a tela abre para todo mundo. O banco recusaria a escrita, mas a
/// pessoa veria a lista.
class PendingReportsPage extends ConsumerWidget {
  const PendingReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDistrictAdmin = ref.watch(isDistrictAdminProvider);
    return isDistrictAdmin.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const _NotForYou(),
      data: (isAdmin) => isAdmin ? const _ReportList() : const _NotForYou(),
    );
  }
}

class _NotForYou extends StatelessWidget {
  const _NotForYou();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Imagens denunciadas')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Só o Administrador do distrito decide sobre imagens denunciadas.\n\n'
            'Se você denunciou uma imagem, ela já foi registrada — não é '
            'preciso fazer mais nada.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _ReportList extends ConsumerWidget {
  const _ReportList();

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    ReportedImage image, {
    required bool removeImage,
  }) async {
    final repository = ref.read(imageReportRepositoryProvider);
    try {
      if (removeImage) {
        // Apaga a linha da capa. O arquivo sai pela fila, e as denúncias desta
        // imagem somem por cascade — o encerramento automático de FR-019.
        await repository.resolveByRemovingImage(image.photoId);
        // Mesma razão do editor de capa: o cron não é garantia no plano
        // gratuito, e aqui a remoção costuma vir de uma denúncia — é o caso em
        // que esperar menos importa mais.
        await ref.read(coverPhotoRepositoryProvider).requestDrain();
        // A listagem também, e não só o item: sem isto, o Grupo cuja capa o
        // Administrador acabou de tirar do ar continuaria exibindo a imagem
        // na lista, porque a rota de baixo segue montada e o provider
        // `autoDispose` mantém o valor em cache.
        if (image.groupId != null) {
          ref.invalidate(groupCoverPhotoProvider(image.groupId!));
          ref.invalidate(groupCoverPhotosProvider);
        } else if (image.actionId != null) {
          ref.invalidate(actionCoverPhotoProvider(image.actionId!));
          ref.invalidate(actionCoverPhotosProvider);
        }
      } else {
        await repository.dismiss(image.photoId);
      }
      ref.invalidate(pendingReportedImagesProvider);
    } catch (_) {
      // FR-031: mesma razão do editor de capa. Num erro de rede o cliente não
      // sabe se a remoção aconteceu, e uma imagem denunciada continuar na
      // lista de pendências — ou sumir dela sem ter saído do ar — são os dois
      // enganos que esta tela não pode cometer. Relê tudo e mostra o que vale.
      ref.invalidate(pendingReportedImagesProvider);
      if (image.groupId != null) {
        ref.invalidate(groupCoverPhotoProvider(image.groupId!));
        ref.invalidate(groupCoverPhotosProvider);
      } else if (image.actionId != null) {
        ref.invalidate(actionCoverPhotoProvider(image.actionId!));
        ref.invalidate(actionCoverPhotosProvider);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não deu pra confirmar. A lista está mostrando o que '
              'vale agora — confira antes de tentar de novo.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingReportedImagesProvider);
    final coverRepository = ref.read(coverPhotoRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Imagens denunciadas')),
      body: pendingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Não deu pra carregar as denúncias agora.'),
        ),
        data: (images) {
          if (images.isEmpty) {
            return const Center(child: Text('Nenhuma imagem denunciada.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: images.length,
            separatorBuilder: (_, _) => const SizedBox(height: 16),
            itemBuilder: (_, index) {
              final image = images[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        coverRepository.publicUrlForPath(image.path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Text('A imagem já não está disponível.'),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            image.reportCount == 1
                                ? '1 denúncia'
                                : '${image.reportCount} denúncias',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          // De onde a imagem veio. Sem isso, o Administrador
                          // decide sobre uma foto sem contexto nenhum.
                          TextButton(
                            onPressed: image.groupId != null
                                ? () => context.push('/grupos/${image.groupId}')
                                : () => context.push('/acoes/${image.actionId}'),
                            child: Text(
                              image.groupId != null
                                  ? 'Ver o Grupo/Ministério'
                                  : 'Ver a Ação',
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Só os motivos. Quem denunciou não vem para esta
                          // tela — a consulta nem pede a coluna (FR-020).
                          for (final reason in image.reasons)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('• $reason'),
                            ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => _resolve(context, ref, image,
                                    removeImage: false),
                                child: const Text('Improcedente'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () => _resolve(context, ref, image,
                                    removeImage: true),
                                child: const Text('Remover imagem'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
