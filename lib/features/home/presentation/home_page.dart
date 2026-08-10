import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../news/news_providers.dart';

/// Primeira tela do app: diz o que ele é, para quem, e como participar.
///
/// Conteúdo estático de propósito — nenhum texto daqui depende de rede, para a
/// Home renderizar por completo offline (SC-005). O único provider observado é
/// [hasProfileProvider], e só dentro de [_MainCallToAction]; todo o resto fica
/// fora de qualquer `AsyncValue`. Embrulhar a página inteira num `.when` faria
/// a Home mostrar um indicador de carregamento no lugar do conteúdo quando não
/// há rede, que é exatamente o que SC-005 proíbe.
///
/// Sem animação de entrada: a forma mais simples de respeitar a preferência de
/// movimento reduzido do sistema (FR-016) é não ter movimento a suprimir.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bloco de identidade — compacto de propósito: é ele que precisa
              // caber sem rolagem em paisagem, em tamanho de fonte padrão.
              Text('Conecta IASD', style: text.headlineMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'O app dos membros das igrejas do distrito de Vitória de Santo '
                'Antão para descobrir e participar de Grupos e Ações.',
                style: text.bodyLarge,
              ),

              const SizedBox(height: AppSpacing.xl),
              const _ConceptCard(
                icon: Icons.groups_outlined,
                title: 'Grupo/Ministério',
                body: 'Comunidade permanente em torno de uma atividade que se '
                    'repete — um ministério, um time, uma turma. Tem horário, '
                    'local e gente que participa.',
              ),
              const SizedBox(height: AppSpacing.md),
              const _ConceptCard(
                icon: Icons.event_outlined,
                title: 'Ação',
                body: 'Encontro pontual, com data, hora e local. Pode nascer '
                    'dentro de um Grupo, por votação, ou ser criada solta por '
                    'qualquer pessoa cadastrada.',
              ),

              const SizedBox(height: AppSpacing.lg),
              Text(
                'Ver Grupos e Ações é livre, sem cadastro. Para participar, '
                'votar ou criar, é preciso um cadastro simples.',
                style: text.bodyMedium,
              ),

              const SizedBox(height: AppSpacing.xl),
              const _MainCallToAction(),

              const SizedBox(height: AppSpacing.xl),
              const Divider(),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => context.push('/privacidade'),
                child: const Text('Política de Privacidade'),
              ),
              TextButton(
                onPressed: () => context.push('/termos'),
                child: const Text('Termos de Uso'),
              ),

              const SizedBox(height: AppSpacing.lg),
              // Rodapé. Texto comum, não decoração: leitor de tela precisa ler,
              // então nada de ExcludeSemantics aqui.
              Center(
                child: Text(
                  'A Deus seja a glória',
                  style: text.titleMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: AppColors.navy,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}

/// Explicação curta de um termo do glossário, com ícone da mesma família
/// Material usada no resto do app (FR-017 — nada de emoji como ícone).
class _ConceptCard extends StatelessWidget {
  const _ConceptCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.navy),
              const SizedBox(width: AppSpacing.sm),
              Text(title, style: text.titleLarge),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(body, style: text.bodyMedium),
        ],
      ),
    );
  }
}

/// Chamada principal única da Home (FR-008), e o único ponto que observa rede.
///
/// Carregando ou em erro cai no neutro "Ver Grupos", que serve a qualquer
/// pessoa: quem não tem Perfil vê os Grupos livremente e encontra o cadastro
/// logo abaixo. O contrário — oferecer "Criar Perfil" a quem já tem — seria um
/// beco sem saída.
class _MainCallToAction extends ConsumerWidget {
  const _MainCallToAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasProfile = ref.watch(hasProfileProvider).value;
    final needsSignup = hasProfile == false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (needsSignup)
          ElevatedButton(
            onPressed: () => context.push('/cadastro'),
            child: const Text('Criar Perfil'),
          )
        else
          ElevatedButton(
            onPressed: () => context.go('/grupos'),
            child: const Text('Ver Grupos/Ministérios'),
          ),
        const SizedBox(height: AppSpacing.sm),
        if (needsSignup)
          OutlinedButton(
            onPressed: () => context.go('/grupos'),
            child: const Text('Ver Grupos/Ministérios'),
          ),
        if (needsSignup) const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          onPressed: () => context.go('/acoes'),
          child: const Text('Ver Ações'),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Para todo mundo, com ou sem Perfil: o que mudou no app não é
        // informação de quem tem cadastro.
        const _NewsButton(),
        // Só para quem tem Perfil: sem Perfil não há o que ver, e a rota
        // redirecionaria ao cadastro. Rótulo em texto, não só ícone — o
        // caminho até o próprio dado não pode depender de adivinhar um
        // desenho.
        if (hasProfile == true) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => context.push('/perfil'),
            icon: const Icon(Icons.person_outline),
            label: const Text('Meu Perfil'),
          ),
        ],
      ],
    );
  }
}

/// Caminho para as Novidades, com aviso quando há item que esta instalação
/// ainda não viu.
///
/// O aviso **não** aparece enquanto o provider carrega: um ponto que pisca a
/// cada abertura do app é pior do que aviso nenhum.
class _NewsButton extends ConsumerWidget {
  const _NewsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasUnseen = ref.watch(hasUnseenNewsProvider).value ?? false;

    return OutlinedButton.icon(
      onPressed: () => context.push('/novidades'),
      icon: const Icon(Icons.campaign_outlined),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Novidades'),
          if (hasUnseen) ...[
            const SizedBox(width: AppSpacing.sm),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
