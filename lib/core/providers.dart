import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/perfil/data/auth_repository.dart';
import '../features/perfil/data/perfil_repository.dart';
import '../features/perfil/domain/church.dart';
import '../features/perfil/domain/profile.dart';
import 'supabase_client.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return AppSupabase.client;
});

final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

/// Id do Usuário da sessão atual — provider dedicado (em vez de acessar
/// `supabaseClientProvider` direto nas telas) pra ficar fácil de sobrescrever
/// em teste de widget sem precisar mockar `SupabaseClient`/`GoTrueClient`.
final currentUserIdProvider = Provider<String?>((ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(supabaseClientProvider).auth.currentUser?.id;
});

/// Sessão atual é anônima? Nulo enquanto não há sessão nenhuma. Provider
/// dedicado pelo mesmo motivo de [currentUserIdProvider]: o roteamento
/// depende disso (sair de /login) e teste de widget precisa sobrescrever sem
/// mockar `SupabaseClient`/`GoTrueClient`.
final isAnonymousProvider = Provider<bool?>((ref) {
  ref.watch(authStateChangesProvider);
  return ref.watch(supabaseClientProvider).auth.currentUser?.isAnonymous;
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

final churchesProvider = FutureProvider<List<Church>>((ref) async {
  return ref.watch(perfilRepositoryProvider).fetchChurches();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

final perfilPublicoProvider = FutureProvider.autoDispose.family<PublicProfile, String>((ref, id) {
  return ref.watch(perfilRepositoryProvider).fetchPerfilPublico(id);
});
