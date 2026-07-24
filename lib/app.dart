import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/acao/presentation/criar_acao_page.dart';
import 'features/acao/presentation/criar_candidata_page.dart';
import 'features/acao/presentation/criar_rodada_page.dart';
import 'features/acao/presentation/detalhe_acao_page.dart';
import 'features/acao/presentation/detalhe_rodada_page.dart';
import 'features/acao/presentation/lista_acoes_page.dart';
import 'features/acao/presentation/lista_rodadas_page.dart';
import 'features/grupo/presentation/criar_grupo_page.dart';
import 'features/grupo/presentation/detalhe_grupo_page.dart';
import 'features/grupo/presentation/editar_grupo_page.dart';
import 'features/grupo/presentation/lista_grupos_page.dart';
import 'features/perfil/presentation/cadastro_perfil_page.dart';
import 'features/perfil/presentation/login_page.dart';
import 'features/perfil/presentation/upgrade_conta_page.dart';

/// Notifica o [GoRouter] pra reavaliar `redirect` sempre que [hasPerfilProvider]
/// muda (ex.: cadastro concluído, upgrade pra Conta).
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(hasPerfilProvider, (_, _) => notifyListeners());
  }
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final hasPerfil = ref.read(hasPerfilProvider).valueOrNull;
      if (hasPerfil == null) return null; // ainda carregando, fica onde está
      // Visitante (sem Perfil) navega livremente por qualquer rota pública
      // (Home, lista/detalhe de Grupo — FR-008 da 001, FR-005 da 002).
      // Só ações concretas (Participar, Criar Grupo...) checam Perfil, via
      // PerfilGuard.exigirPerfil no próprio botão — não aqui no redirect
      // global. A única exceção é sair da tela de cadastro depois de já
      // ter Perfil, pra não deixar a pessoa "presa" nela.
      if (hasPerfil && state.matchedLocation == '/cadastro') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/home'),
      GoRoute(
        path: '/cadastro',
        builder: (context, state) => const CadastroPerfilPage(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const ListaGruposPage(),
      ),
      GoRoute(
        path: '/upgrade-conta',
        builder: (context, state) => const UpgradeContaPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/grupos/novo',
        builder: (context, state) => const CriarGrupoPage(),
      ),
      GoRoute(
        path: '/grupos/:id',
        builder: (context, state) => DetalheGrupoPage(grupoId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/grupos/:id/editar',
        builder: (context, state) => EditarGrupoPage(grupoId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/acoes',
        builder: (context, state) => const ListaAcoesPage(),
      ),
      GoRoute(
        path: '/acoes/novo',
        builder: (context, state) => const CriarAcaoPage(),
      ),
      GoRoute(
        path: '/acoes/:id',
        builder: (context, state) => DetalheAcaoPage(acaoId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/grupos/:id/rodadas',
        builder: (context, state) => ListaRodadasPage(grupoId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/grupos/:id/rodadas/novo',
        builder: (context, state) => CriarRodadaPage(grupoId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/rodadas/:id/candidatas/novo',
        builder: (context, state) => CriarCandidataPage(rodadaId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/rodadas/:id',
        builder: (context, state) => DetalheRodadaPage(rodadaId: state.pathParameters['id']!),
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
      title: 'IASD Distrito Vitória de Santo Antão',
      debugShowCheckedModeBanner: kDebugMode,
      theme: AppTheme.light(),
      routerConfig: router,
    );
  }
}
