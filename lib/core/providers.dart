import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/perfil/data/auth_repository.dart';
import '../features/perfil/data/perfil_repository.dart';
import '../features/perfil/domain/igreja.dart';
import 'supabase_client.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return AppSupabase.client;
});

final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

final perfilRepositoryProvider = Provider<PerfilRepository>((ref) {
  return PerfilRepository(ref.watch(supabaseClientProvider));
});

/// Re-executa sempre que o estado de auth muda (ex.: upgrade pra Conta),
/// pra manter o roteamento (T008) consistente com a sessão atual.
final hasPerfilProvider = FutureProvider<bool>((ref) async {
  ref.watch(authStateChangesProvider);
  return ref.watch(perfilRepositoryProvider).hasPerfil();
});

final igrejasProvider = FutureProvider<List<Igreja>>((ref) async {
  return ref.watch(perfilRepositoryProvider).fetchIgrejas();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});
