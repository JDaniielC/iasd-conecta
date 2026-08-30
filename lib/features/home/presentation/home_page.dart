import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../invite/invite_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../news/news_providers.dart';

/// Primeira tela do app: diz o que ele é, para quem, e como participar.
///
/// Conteúdo estático de propósito — nenhum texto daqui depende de rede, para a
/// Home renderizar por completo offline (SC-005). Os únicos providers
/// observados são [hasProfileProvider] (no cabeçalho e em [_MainCallToAction])
/// e os de [_QuickLinksRow]; todo o resto fica fora de qualquer [AsyncValue].
/// Embrulhar a página inteira num `.when` faria a Home mostrar um indicador de
/// carregamento no lugar do conteúdo quando não há rede, que é exatamente o
/// que SC-005 proíbe.
///
/// Sem animação de entrada: a forma mais simples de respeitar a preferência de
/// movimento reduzido do sistema (FR-016) é não ter movimento a suprimir.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // NÃO `extendBodyBehindAppBar`: a AppBar continua opaca (mesmo tom do
      // topo do gradiente do herói) e com sua própria faixa de altura. Uma
      // AppBar "transparente" sobrepondo o corpo continua sólida pro toque —
      // um botão do herói que role até encostar no topo fica embaixo dela e
      // para de responder a toque. Pego por `router_visitante_test.dart`.
      appBar: AppBar(
        backgroundColor: AppColors.heroDeep,
        elevation: 0,
        foregroundColor: Colors.white,
        // "Meu Perfil" mora aqui como ícone quando há Conta — deixou de ser
        // um botão inteiro no corpo da tela porque, com Perfil, é o caminho
        // mais lido: fica onde a mão já procura em qualquer app.
        actions: const [_ProfileHeaderButton()],
      ),
      body: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeroSection(),
            _BelowHeroSection(),
          ],
        ),
      ),
    );
  }
}

/// O bloco escuro do topo: identidade, tagline e as duas chamadas de
/// navegação. `logo.png` entra como brasa por trás do texto — a mesma peça
/// gráfica do app, não um fundo genérico.
class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.heroDeep, AppColors.navy],
          ),
        ),
        child: Stack(
          children: [
            // A brasa: girada e clareada, encostada no canto — presença sem
            // competir com o texto.
            Positioned(
              top: -40,
              right: -80,
              child: Opacity(
                opacity: 0.5,
                child: Transform.rotate(
                  angle: 0.35,
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 340,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 16, color: AppColors.accent),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            'Vitória de Santo Antão',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: AppColors.accent,
                                  letterSpacing: 1.1,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Conecta IASD',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Conecte-se. Participe. Faça acontecer.',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'O app dos membros das igrejas do distrito de Vitória de '
                      'Santo Antão para descobrir e participar de Grupos e '
                      'Ações.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const _MainCallToAction(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// O resto da tela: fundo claro, os dois conceitos, o aviso de cadastro, os
/// atalhos e as páginas legais.
class _BelowHeroSection extends StatelessWidget {
  const _BelowHeroSection();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('O que são Grupos e Ações?', style: text.headlineSmall),
          const SizedBox(height: AppSpacing.md),
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

          const SizedBox(height: AppSpacing.lg),
          const _QuickLinksRow(),

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
              Flexible(
                child: Text(
                  title,
                  style: text.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(body, style: text.bodyMedium),
        ],
      ),
    );
  }
}

/// Chamada principal única da Home (FR-008), sobre o fundo escuro do herói —
/// o único ponto do herói que observa rede.
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
            style: _heroPrimaryButtonStyle,
            onPressed: () => context.push('/cadastro'),
            child: const Text('Criar Perfil'),
          )
        else
          ElevatedButton(
            style: _heroPrimaryButtonStyle,
            onPressed: () => context.go('/grupos'),
            child: const Text('Ver Grupos/Ministérios'),
          ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            if (needsSignup) ...[
              Expanded(
                child: OutlinedButton(
                  style: _heroSecondaryButtonStyle,
                  onPressed: () => context.go('/grupos'),
                  child: const Text('Ver Grupos/Ministérios'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: OutlinedButton(
                style: _heroSecondaryButtonStyle,
                onPressed: () => context.go('/acoes'),
                child: const Text('Ver Ações'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Botão claro sobre o herói escuro — o inverso do tema padrão (navy sobre
/// branco), porque aqui o fundo já é navy.
final _heroPrimaryButtonStyle = ElevatedButton.styleFrom(
  backgroundColor: Colors.white,
  foregroundColor: AppColors.navy,
  minimumSize: const Size(double.infinity, 52),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
);

final _heroSecondaryButtonStyle = OutlinedButton.styleFrom(
  foregroundColor: Colors.white,
  side: const BorderSide(color: Colors.white54),
  minimumSize: const Size(0, 48),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
);

/// Ícone de "Meu Perfil" no cabeçalho, só quando há Perfil — troca o antigo
/// botão de texto no corpo da tela. Sem Perfil não há o que ver, e a rota
/// redirecionaria ao cadastro.
class _ProfileHeaderButton extends ConsumerWidget {
  const _ProfileHeaderButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasProfile = ref.watch(hasProfileProvider).value ?? false;
    if (!hasProfile) return const SizedBox.shrink();

    return IconButton(
      tooltip: 'Meu Perfil',
      icon: const Icon(Icons.person_outline),
      onPressed: () => context.push('/perfil'),
    );
  }
}

/// Novidades (todo mundo) e Convites (só com Perfil), lado a lado — os dois
/// atalhos que não são a navegação principal, mas merecem estar visíveis sem
/// depender do cabeçalho de outra tela.
class _QuickLinksRow extends ConsumerWidget {
  const _QuickLinksRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasProfile = ref.watch(hasProfileProvider).value ?? false;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        const _NewsButton(),
        // Só para quem tem Perfil: sem Perfil não há o que ver, e a rota
        // redirecionaria ao cadastro.
        if (hasProfile) const _InvitesButton(),
      ],
    );
  }
}

/// Caminho para os convites recebidos, com quantos estão em aberto.
///
/// O número é a mitigação registrada no design da change `convite-para-acao`
/// para ela não ter notificação: sem push e sem e-mail, o convite só apareceria
/// para quem lembrasse de abrir a tela. Como no aviso de Novidades, o contador
/// **não** aparece enquanto carrega — um número que pisca a cada abertura é
/// pior do que número nenhum.
class _InvitesButton extends ConsumerWidget {
  const _InvitesButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(openInvitesCountProvider).value ?? 0;

    return OutlinedButton.icon(
      onPressed: () => context.push('/convites'),
      icon: const Icon(Icons.mail_outline),
      label: Text(open > 0 ? 'Convites ($open)' : 'Convites'),
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
