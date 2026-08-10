import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/image_upload.dart';
import '../../image_report/presentation/report_image_sheet.dart';
import '../cover_photo_providers.dart';
import '../domain/cover_photo.dart';
import 'cover_photo_advice_sheet.dart';

/// A capa, como ela aparece.
///
/// **Grupo/Ação sem capa não deixa buraco** (FR-002): quando não há imagem,
/// este widget ocupa zero — não desenha moldura vazia, nem ícone de "sem foto",
/// nem espaço reservado. A maioria dos Grupos não vai ter capa, e um retângulo
/// cinza repetido na lista inteira é pior do que nada.
///
/// **Quando há capa, o espaço é reservado antes de a imagem chegar** (FR-007).
/// Sem isso a lista pula enquanto carrega, e quem estava lendo perde a linha —
/// é a razão de a proporção ser fixa e não derivada da imagem.
class CoverPhotoView extends StatelessWidget {
  const CoverPhotoView({
    super.key,
    required this.photo,
    required this.imageUrl,
    this.borderRadius,
  });

  final CoverPhoto? photo;
  final String? imageUrl;
  final BorderRadius? borderRadius;

  /// Proporção fixa, deliberada.
  ///
  /// Derivar a proporção da imagem exigiria conhecer a imagem — o que só
  /// acontece depois de baixá-la, que é exatamente o momento em que a lista
  /// não pode pular.
  static const aspectRatio = 16 / 9;

  @override
  Widget build(BuildContext context) {
    if (photo == null || imageUrl == null) return const SizedBox.shrink();

    final radius = borderRadius ?? BorderRadius.circular(12);

    return ClipRRect(
      borderRadius: radius,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Image.network(
            imageUrl!,
            // `cover` recorta; `fill` deformaria. Uma imagem muito alta ou
            // muito larga (o edge case da spec) sai cortada, e não esticada —
            // rosto achatado é pior do que rosto fora do enquadramento.
            fit: BoxFit.cover,
            // Enquanto não chega, o Container colorido acima já segura o
            // espaço. Sem `frameBuilder` a imagem apareceria de um quadro para
            // o outro sobre um vazio.
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) return child;
              return const SizedBox.expand();
            },
            // Imagem que não carrega não pode virar exceção vermelha na lista
            // — some, e o resto da tela continua íntegro.
            errorBuilder: (_, _, _) => const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// A capa **com** as ações de quem administra.
///
/// **Enviar e remover são permissões separadas, e essa separação é o conserto
/// de um erro.** Quando eram um `canManage` só, dar ao Administrador do
/// distrito o poder de remover em qualquer estado (FR-011) deu junto o poder de
/// **publicar** capa em Grupo arquivado e em Ação cancelada. O caso ruim é
/// concreto: o gatilho `acoes_remover_capa_ao_cancelar` só dispara na transição
/// `null → não-nulo` de `cancelada_em`, então capa enviada **depois** do
/// cancelamento não sai por caminho nenhum.
///
/// A regra: [canRemove] vale para quem administra **sempre**; [canUpload]
/// exclui o que é histórico. Quem decide é a tela, porque a regra é diferente
/// em Grupo (dono) e em Ação (criador). O banco é quem garante —
/// `fotos_capa_insert_admin` e `fotos_capa_delete_admin`; aqui é só o que a
/// pessoa **vê**.
class CoverPhotoEditor extends ConsumerStatefulWidget {
  const CoverPhotoEditor({
    super.key,
    required this.canUpload,
    required this.canRemove,
    this.groupId,
    this.actionId,
  }) : assert(
          (groupId == null) != (actionId == null),
          'Exatamente um dono: Grupo ou Ação',
        );

  /// Enviar capa nova ou trocar a existente. Falso no que é histórico.
  final bool canUpload;

  /// Tirar a capa do ar. Vale mesmo no que é histórico — imagem imprópria num
  /// Grupo arquivado continua pública (FR-011).
  final bool canRemove;
  final String? groupId;
  final String? actionId;

  @override
  ConsumerState<CoverPhotoEditor> createState() => _CoverPhotoEditorState();
}

class _CoverPhotoEditorState extends ConsumerState<CoverPhotoEditor> {
  bool _busy = false;

  /// Invalida a capa **e as listagens**.
  ///
  /// Invalidar só o provider de item único deixava a listagem mostrando a
  /// imagem removida: com `context.push`, a rota de baixo continua montada, o
  /// provider `autoDispose` da lista mantém o listener, e o valor em cache
  /// sobrevive à volta. Uma imagem removida continuar aparecendo é pior que a
  /// janela de 60 segundos do cache de borda, e essa a Política até declara.
  ///
  /// A família inteira é invalidada porque a chave é a lista de ids da tela,
  /// que este widget não conhece.
  void _invalidatePhoto() {
    if (widget.groupId != null) {
      ref.invalidate(groupCoverPhotoProvider(widget.groupId!));
      ref.invalidate(groupCoverPhotosProvider);
    } else {
      ref.invalidate(actionCoverPhotoProvider(widget.actionId!));
      ref.invalidate(actionCoverPhotosProvider);
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickAndUpload() async {
    // O aviso vem ANTES do seletor, sempre — inclusive na troca. Ver
    // CoverPhotoAdviceSheet.
    final wantsToContinue = await CoverPhotoAdviceSheet.show(context);
    if (!wantsToContinue || !mounted) return;

    setState(() => _busy = true);
    try {
      final image = await ImageUpload().pick(
        maxBytes: coverPhotoMaxBytes,
        allowedMimeTypes: coverPhotoAllowedMimeTypes,
      );
      if (image == null) return; // desistiu no seletor

      final repository = ref.read(coverPhotoRepositoryProvider);
      if (widget.groupId != null) {
        await repository.uploadForGroup(groupId: widget.groupId!, image: image);
      } else {
        await repository.uploadForAction(
          actionId: widget.actionId!,
          image: image,
        );
      }
      _invalidatePhoto();
      // Trocar a capa enfileira a ANTIGA — a fila também precisa ser drenada
      // aqui, não só na remoção.
      await repository.requestDrain();
    } on ImageRejected catch (e) {
      // A mensagem já vem em português e pronta para a tela — a tela não
      // traduz nada.
      _say(e.message);
    } catch (_) {
      // FR-010/SC-009: falha de envio não altera o Grupo/Ação e não derruba a
      // tela. Nada foi gravado, e quem estava preenchendo algo continua com o
      // que preencheu.
      _say('Não deu pra enviar a imagem agora. Tente de novo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(CoverPhoto photo) async {
    setState(() => _busy = true);
    try {
      final repository = ref.read(coverPhotoRepositoryProvider);
      await repository.remove(photo);
      _invalidatePhoto();
      // Pede a limpeza do arquivo agora, sem esperar o cron — que no plano
      // gratuito para junto com o banco pausado. Não lança.
      await repository.requestDrain();
    } catch (_) {
      _say('Não deu pra remover a imagem agora. Tente de novo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoAsync = widget.groupId != null
        ? ref.watch(groupCoverPhotoProvider(widget.groupId!))
        : ref.watch(actionCoverPhotoProvider(widget.actionId!));

    // Enquanto carrega, e em erro, a tela não mostra nada de capa. Erro de
    // leitura de capa não pode impedir de ver o Grupo.
    final photo = photoAsync.value;
    final imageUrl = photo == null
        ? null
        : ref.read(coverPhotoRepositoryProvider).publicUrlFor(photo);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CoverPhotoView(photo: photo, imageUrl: imageUrl),
        // FR-015: denunciar parte **da própria imagem**, e está disponível
        // para qualquer pessoa — inclusive Visitante sem cadastro. É o caminho
        // de quem vê a foto de um filho e precisa pedir a retirada; fazer isso
        // depender de cadastro seria pedir os dados dela para retirar os da
        // criança.
        if (photo != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () =>
                  ReportImageSheet.show(context, photoId: photo.id),
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: const Text('Denunciar imagem'),
            ),
          ),
        if (widget.canUpload || (widget.canRemove && photo != null)) ...[
          if (photo != null) const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.canUpload)
                TextButton.icon(
                  onPressed: _busy ? null : _pickAndUpload,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(photo == null ? 'Adicionar capa' : 'Trocar capa'),
                ),
              if (widget.canRemove && photo != null)
                TextButton.icon(
                  onPressed: _busy ? null : () => _remove(photo),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remover capa'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
