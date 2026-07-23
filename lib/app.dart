import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/home_page.dart';
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
      final local = state.matchedLocation;
      // /login fica fora do gate: é exatamente pra quem ainda não tem Perfil
      // NESTE aparelho mas já tem Conta em outro (recuperação, US3).
      if (local == '/login') return null;
      if (!hasPerfil && local != '/cadastro') return '/cadastro';
      if (hasPerfil && local == '/cadastro') return '/home';
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
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/upgrade-conta',
        builder: (context, state) => const UpgradeContaPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
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
