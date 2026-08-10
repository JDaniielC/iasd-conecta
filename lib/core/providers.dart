import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/profile/data/auth_repository.dart';
import '../features/profile/data/profile_repository.dart';
import '../features/profile/domain/church.dart';
import '../features/profile/domain/profile.dart';
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

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});

/// Re-executa sempre que o estado de auth muda (ex.: upgrade pra Conta),
/// pra manter o roteamento (T008) consistente com a sessão atual.
final hasProfileProvider = FutureProvider<bool>((ref) async {
  ref.watch(authStateChangesProvider);
  return ref.watch(profileRepositoryProvider).hasProfile();
});

/// O Perfil da própria pessoa, inteiro. Diferente de `publicProfileProvider`,
/// que é a projeção que os outros veem, este é o dado como está guardado — é o
/// direito de acesso da LGPD art. 18, II.
final myProfileProvider = FutureProvider<Profile>((ref) async {
  ref.watch(authStateChangesProvider);
  return ref.watch(profileRepositoryProvider).fetchMyProfile();
});

final churchesProvider = FutureProvider<List<Church>>((ref) async {
  return ref.watch(profileRepositoryProvider).fetchChurches();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

final publicProfileProvider = FutureProvider.autoDispose.family<PublicProfile, String>((ref, id) {
  return ref.watch(profileRepositoryProvider).fetchPublicProfile(id);
});

/// Relógio do app, injetável.
///
/// Existe para o encerramento de Ação (feature 011) ser testável: sem isto,
/// "Ação de 4h01 atrás não aparece na lista" viraria um teste que depende do
/// relógio real da máquina, montando dados relativos a `DateTime.now()` e
/// falhando conforme a hora em que roda.
///
/// Regra de uso: quem **decide** olhando o relógio lê daqui; quem **carimba**
/// um instante para gravar (ex.: `cancelledAt`) usa `DateTime.now()` direto.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
