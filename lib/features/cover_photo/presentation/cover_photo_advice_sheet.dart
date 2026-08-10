import 'package:flutter/material.dart';

/// A **parada obrigatória antes do seletor de arquivo** (FR-004, FR-005).
///
/// Não é um texto ao lado do botão: é um passo que a pessoa precisa reconhecer
/// para o seletor abrir. A diferença é o que faz a barreira existir — aviso
/// escrito ao lado do botão é lido por ninguém, e a pergunta que esta feature
/// precisa fazer ("esta imagem tem gente nela?") só funciona **antes** da
/// escolha. Depois de escolher a foto da filha, a pessoa já decidiu.
///
/// Aparece **toda vez**, inclusive na troca de uma capa que já existe, e
/// **não** tem "não mostrar de novo" (FR-005, research D-005): isso
/// transformaria a barreira em nada depois do primeiro uso, e quem envia muitas
/// imagens é exatamente quem mais precisa vê-la.
///
/// Devolve `true` quando a pessoa quer seguir para o seletor.
class CoverPhotoAdviceSheet extends StatelessWidget {
  const CoverPhotoAdviceSheet({super.key});

  /// Abre o aviso e devolve `true` se a pessoa seguiu.
  static Future<bool> show(BuildContext context) async {
    final chosen = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const CoverPhotoAdviceSheet(),
    );
    return chosen ?? false;
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
            Text(
              'Use uma imagem ilustrativa',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Logo do ministério, arte do evento, foto do local.',
            ),
            const SizedBox(height: 12),
            // O motivo em uma frase, e é o motivo verdadeiro — não apelo
            // jurídico. "Qualquer pessoa na internet vê" é o que convence, e é
            // literalmente o que acontece: o bucket é público (FR-008).
            Text(
              'Não envie foto de pessoas, e nunca de crianças ou adolescentes '
              '— qualquer pessoa na internet consegue ver esta imagem, mesmo '
              'sem cadastro no app.',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Escolher imagem'),
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
