import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/image_report/presentation/pending_reports_page.dart';
import 'features/action/presentation/create_action_page.dart';
import 'features/action/presentation/create_candidate_page.dart';
import 'features/action/presentation/create_voting_round_page.dart';
import 'features/action/presentation/action_detail_page.dart';
import 'features/invite/presentation/invite_to_action_page.dart';
import 'features/invite/presentation/received_invites_page.dart';
import 'features/notification/presentation/notifications_page.dart';
import 'features/action/presentation/voting_round_detail_page.dart';
import 'features/action/presentation/action_list_page.dart';
import 'features/action/presentation/voting_round_list_page.dart';
import 'features/suggested_action/presentation/manage_suggested_actions_page.dart';
import 'features/district_admin/presentation/manage_churches_page.dart';
import 'features/district_admin/presentation/promote_admin_page.dart';
import 'features/group/presentation/create_group_page.dart';
import 'features/chat/chat_providers.dart';
import 'features/chat/presentation/chat_gate_page.dart';
import 'features/chat/presentation/message_reports_page.dart';
import 'features/group/presentation/group_detail_page.dart';
import 'features/group/presentation/edit_group_page.dart';
import 'features/group/presentation/group_list_page.dart';
import 'features/group/presentation/my_groups_page.dart';
import 'features/home/presentation/home_page.dart';
import 'features/leadership/presentation/declare_leadership_page.dart';
import 'features/leadership/presentation/pending_declarations_page.dart';
import 'features/group/presentation/archived_groups_page.dart';
import 'features/news/presentation/news_page.dart';
import 'features/profile/presentation/my_profile_page.dart';
import 'features/legal/presentation/consent_versions_page.dart';
import 'features/legal/presentation/privacy_policy_page.dart';
import 'features/legal/presentation/terms_of_use_page.dart';
import 'features/profile/presentation/profile_signup_page.dart';
import 'features/profile/presentation/login_page.dart';
import 'features/profile/presentation/delete_account_page.dart';
import 'features/profile/presentation/upgrade_account_page.dart';

/// Notifica o [GoRouter] pra reavaliar `redirect` sempre que [hasPerfilProvider]
/// muda (ex.: cadastro concluído, upgrade pra Conta).
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(hasProfileProvider, (_, _) => notifyListeners());
  }
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final hasProfile = ref.read(hasProfileProvider).value;
      if (hasProfile == null) return null; // ainda carregando, fica onde está
      // Visitante (sem Perfil) navega livremente por qualquer rota pública
      // (Home, lista/detalhe de Grupo — FR-008 da 001, FR-005 da 002).
      // Só ações concretas (Participar, Criar Grupo...) checam Perfil, via
      // PerfilGuard.exigirPerfil no próprio botão — não aqui no redirect
      // global. A exceção é sair de /cadastro depois do cadastro concluído,
      // pra não deixar a pessoa "presa" nela — a tela não navega sozinha, só
      // invalida `hasPerfilProvider` e espera este redirect. LoginPage NÃO
      // segue esse padrão: ela navega direto (`context.go('/home')`), porque
      // esse redirect só reavalia quando hasProfileProvider MUDA de valor, e
      // uma Conta que já tinha Perfil antes de logar deixa o valor igual —
      // ver o comentário em login_page.dart e
      // test/widget/login_page_test.dart.
      if (hasProfile && state.matchedLocation == '/cadastro') return '/home';
      // `== false`, não `!hasProfile`: o caso "ainda carregando" já saiu acima,
      // e inverter isso empurraria ao cadastro quem só está esperando a rede.
      // O redirect é o que cumpre FR-005 em web, onde `/perfil` é digitável na
      // barra de endereço — esconder o link não basta.
      if (hasProfile == false && state.matchedLocation == '/perfil') {
        return '/cadastro';
      }
      // /login sai por sessão deixar de ser anônima, não por ter Perfil:
      // quem entra numa Conta sem Perfil vira Visitante em /home (rota
      // pública), em vez de ficar preso na tela de entrar.
      if (ref.read(isAnonymousProvider) == false &&
          state.matchedLocation == '/login') {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/home'),
      GoRoute(
        path: '/cadastro',
        builder: (context, state) => const ProfileSignupPage(),
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomePage()),
      GoRoute(
        path: '/upgrade-conta',
        builder: (context, state) => const UpgradeAccountPage(),
      ),
      GoRoute(
        path: '/delete-account',
        builder: (context, state) => const DeleteAccountPage(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      // `/grupos` vem antes de `/grupos/:id`: go_router casa na ordem de
      // declaração, e a listagem não pode competir com o parâmetro de id.
      GoRoute(
        path: '/grupos',
        builder: (context, state) => const GroupListPage(),
      ),
      GoRoute(
        path: '/meus-grupos',
        builder: (context, state) => const MyGroupsPage(),
      ),
      GoRoute(
        path: '/grupos/novo',
        builder: (context, state) => const CreateGroupPage(),
      ),
      GoRoute(
        path: '/grupos/:id',
        builder: (context, state) =>
            GroupDetailPage(groupId: state.pathParameters['id']!),
      ),
      // Change `chat-de-grupo-e-acao`. A conversa é ROTA PRÓPRIA e não aba da
      // página de detalhe: as duas páginas de detalhe são coluna única sem
      // abas, e na largura de celular uma conversa dentro de aba disputa
      // espaço com o teclado e com a rolagem da página que a contém. A
      // entrada condicional continua no detalhe.
      GoRoute(
        path: '/grupos/:id/conversa',
        builder: (context, state) =>
            ChatGatePage(space: ChatSpace.group(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/grupos/:id/denuncias',
        builder: (context, state) => MessageReportsPage(
          space: ChatSpace.group(state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/grupos/:id/editar',
        builder: (context, state) =>
            EditGroupPage(groupId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/acoes',
        builder: (context, state) => const ActionListPage(),
      ),
      GoRoute(
        path: '/acoes/novo',
        builder: (context, state) => const CreateActionPage(),
      ),
      GoRoute(
        path: '/acoes/:id',
        builder: (context, state) =>
            ActionDetailPage(actionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/acoes/:id/conversa',
        builder: (context, state) =>
            ChatGatePage(space: ChatSpace.action(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/acoes/:id/denuncias',
        builder: (context, state) => MessageReportsPage(
          space: ChatSpace.action(state.pathParameters['id']!),
        ),
      ),
      // Change `convite-para-acao`. A rota de convidar é filha da Ação porque o
      // convite não existe sem ela; `/convites` é da pessoa, não de uma Ação.
      GoRoute(
        path: '/acoes/:id/convidar',
        builder: (context, state) =>
            InviteToActionPage(actionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/notificacoes',
        builder: (context, state) => const NotificationsPage(),
      ),
      GoRoute(
        path: '/convites',
        builder: (context, state) => const ReceivedInvitesPage(),
      ),
      GoRoute(
        path: '/grupos/:id/rodadas',
        builder: (context, state) =>
            VotingRoundListPage(groupId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/grupos/:id/rodadas/novo',
        builder: (context, state) =>
            CreateVotingRoundPage(groupId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/rodadas/:id/candidatas/novo',
        builder: (context, state) =>
            CreateCandidatePage(votingRoundId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/rodadas/:id',
        builder: (context, state) =>
            VotingRoundDetailPage(votingRoundId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/district-admin/promote',
        builder: (context, state) => const PromoteAdminPage(),
      ),
      GoRoute(
        path: '/district-admin/churches',
        builder: (context, state) => const ManageChurchesPage(),
      ),
      GoRoute(
        path: '/grupos/:id/leadership/declare',
        builder: (context, state) =>
            DeclareLeadershipPage(groupId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/leadership/pending',
        builder: (context, state) => const PendingDeclarationsPage(),
      ),
      GoRoute(
        path: '/district-admin/suggested-actions',
        builder: (context, state) => const ManageSuggestedActionsPage(),
      ),
      GoRoute(
        path: '/novidades',
        builder: (context, state) => const NewsPage(),
      ),
      GoRoute(
        path: '/perfil',
        builder: (context, state) => const MyProfilePage(),
      ),
      GoRoute(
        path: '/district-admin/grupos-arquivados',
        builder: (context, state) => const ArchivedGroupsPage(),
      ),
      GoRoute(
        path: '/district-admin/imagens-denunciadas',
        builder: (context, state) => const PendingReportsPage(),
      ),
      GoRoute(
        path: '/district-admin/consentimentos',
        builder: (context, state) => const ConsentVersionsPage(),
      ),
      GoRoute(
        path: '/privacidade',
        builder: (context, state) => const PrivacyPolicyPage(),
      ),
      GoRoute(
        path: '/termos',
        builder: (context, state) => const TermsOfUsePage(),
      ),
    ],
  );
});

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      title: 'Conecta IASD',
      debugShowCheckedModeBanner: kDebugMode,
      theme: AppTheme.light(),
      routerConfig: router,
    );
  }
}
