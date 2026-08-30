import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../district_admin/district_admin_providers.dart';
import '../domain/retention_limits.dart';
import '../domain/retention_run.dart';
import '../retention_providers.dart';

final _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

/// A promessa de prazo, observada — "a faxina de retenção rodou ontem?" sem
/// ir ao banco à mão.
///
/// O portão de acesso mora AQUI, no mesmo molde de `PendingReportsPage`: o
/// provider de Administrador é assíncrono e vale `null` durante a navegação,
/// então um `redirect` no roteador não bastaria.
class RetentionWatchPage extends ConsumerWidget {
  const RetentionWatchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDistrictAdmin = ref.watch(isDistrictAdminProvider);
    return isDistrictAdmin.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const _NotForYou(),
      data: (isAdmin) => isAdmin ? const _RunList() : const _NotForYou(),
    );
  }
}

class _NotForYou extends StatelessWidget {
  const _NotForYou();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Faxinas de retenção')),
      body: const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: Text(
            'Só o Administrador do distrito acompanha as faxinas de '
            'retenção.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _RunList extends ConsumerWidget {
  const _RunList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runsAsync = ref.watch(latestRetentionRunsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Faxinas de retenção')),
      body: runsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Não deu pra carregar o rastro agora.'),
        ),
        data: (runs) {
          // Por VALOR CONHECIDO (RetentionJob.values), não pelo que veio do
          // banco: uma faxina sem nenhuma linha não aparece na consulta, e é
          // exatamente o caso "nunca rodou" que este loop precisa mostrar —
          // ver a tarefa 4.3 e o design, seção "Migration Plan".
          final byJob = {for (final r in runs) r.job: r};

          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: RetentionJob.values.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              final job = RetentionJob.values[index];
              return _RunCard(job: job, run: byJob[job.dbValue]);
            },
          );
        },
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({required this.job, required this.run});

  final RetentionJob job;
  final RetentionRun? run;

  @override
  Widget build(BuildContext context) {
    final run = this.run;
    if (run == null) {
      return _Card(
        title: job.label,
        icon: Icons.help_outline,
        // "Com todas as letras" (tarefa 4.3): no primeiro dia depois da
        // subida este é o estado NORMAL, não um alarme — por isso o ícone
        // neutro e não o de alerta.
        body: const Text('Nunca rodou desde que este rastro existe.'),
      );
    }

    final isStale =
        DateTime.now().toUtc().difference(run.ranAt) > RetentionLimits.staleAfter;
    final when = _dateFormat.format(run.ranAt.toLocal());
    // "pelo próprio app" e não "ao abrir a tela": só
    // `expurgar_mensagens_de_acao` tem esse segundo gatilho de verdade — as
    // outras duas faxinas nunca são chamadas pelo cliente (achado da
    // verificação promessa-vs-execução desta change). Um texto mais
    // específico prometeria um caminho que só existe para uma das três.
    final by = switch (run.triggeredBy) {
      RetentionTrigger.cron => 'pela rotina automática do banco',
      RetentionTrigger.app => 'pelo próprio app',
    };

    return _Card(
      title: job.label,
      icon: isStale ? Icons.warning_amber_outlined : Icons.check_circle_outline,
      iconColor: isStale ? Theme.of(context).colorScheme.error : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Última execução: $when — apagou ${run.deletedCount} linha(s), '
              'disparada $by.'),
          if (isStale) ...[
            const SizedBox(height: AppSpacing.xs),
            // "Não há registro desde X", e NÃO "a faxina não rodou" (tarefa
            // 4.4): o registro é `exception`-safe de propósito — pode ter
            // rodado e falhado só ao se registrar. A tela diz o que ela sabe.
            Text(
              'Atrasada — sem registro novo desde $when.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.icon,
    required this.body,
    this.iconColor,
  });

  final String title;
  final IconData icon;
  final Color? iconColor;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  body,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
