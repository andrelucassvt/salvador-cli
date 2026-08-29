import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/git_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/git_state.dart';

/// Area central do modo Git: resumo do snapshot com branch/HEAD, estado
/// sujo/limpo, ahead/behind, contagens e acoes para estados invalidos.
class GitWorkspace extends StatelessWidget {
  const GitWorkspace({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GitCubit>();
    return BlocBuilder<GitCubit, GitState>(
      builder: (context, state) {
        final Widget content = switch (state) {
          GitEmpty() => const _GitHint(
            icon: Icons.account_tree_outlined,
            title: 'Git',
            message: 'Selecione um projeto para ver o status Git.',
          ),
          GitLoading(previous: null) => const _GitLoadingView(),
          GitLoading(previous: final previous?) => _GitSummary(
            snapshot: previous,
            refreshing: true,
            onRefresh: cubit.refresh,
          ),
          GitLoaded(snapshot: final snapshot) => _GitSummary(
            snapshot: snapshot,
            refreshing: false,
            onRefresh: cubit.refresh,
          ),
          GitNotRepository() => _GitHint(
            icon: Icons.folder_off_outlined,
            title: 'Sem repositório',
            message: 'Esta pasta não é um repositório Git.',
            action: cubit.refresh,
          ),
          GitRepositoryOutsideRoot(topLevel: final topLevel) => _GitHint(
            icon: Icons.folder_open_outlined,
            title: 'Repositório fora da raiz',
            message: topLevel == null
                ? 'O repositório Git está acima desta pasta. Abra o diretório real do repositório como raiz.'
                : 'O repositório Git está em "$topLevel". Abra essa pasta como raiz para ver o status Git.',
            action: cubit.refresh,
          ),
          GitFailure(message: final message) => _GitHint(
            icon: Icons.error_outline_rounded,
            title: 'Falha ao acessar o Git',
            message: message,
            action: cubit.refresh,
          ),
        };
        return Container(
          key: const Key('git-workspace'),
          color: shell,
          child: content,
        );
      },
    );
  }
}

class _GitSummary extends StatelessWidget {
  const _GitSummary({
    required this.snapshot,
    required this.refreshing,
    required this.onRefresh,
  });

  final GitSnapshot snapshot;
  final bool refreshing;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final repository = snapshot.repository;
    final branch = repository.branch ?? 'HEAD desanexado';
    return Column(
      children: [
        if (refreshing) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 30, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: snapshot.clean
                            ? const Color(0xFFE2F5EC)
                            : const Color(0xFFFFEFE9),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        snapshot.clean ? 'limpo' : 'sujo',
                        style: TextStyle(
                          color: snapshot.clean
                              ? const Color(0xFF2E7D57)
                              : coral,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        branch,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      'HEAD ${_short(repository.headOid)}',
                      style: const TextStyle(
                        color: muted,
                        fontSize: 11,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                    if (snapshot.upstream != null) ...[
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.call_split_rounded,
                        size: 12,
                        color: muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        snapshot.upstream!,
                        style: const TextStyle(
                          color: muted,
                          fontSize: 11,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
                    Text(
                      'ahead',
                      style: const TextStyle(
                        color: Color(0xFF2E7D57),
                        fontSize: 11,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                    Text(
                      '${snapshot.ahead}',
                      style: const TextStyle(
                        color: Color(0xFF2E7D57),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'behind',
                      style: const TextStyle(
                        color: Color(0xFFB3492E),
                        fontSize: 11,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                    Text(
                      '${snapshot.behind}',
                      style: const TextStyle(
                        color: Color(0xFFB3492E),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatChip(
                      label: 'branch',
                      value: '${snapshot.localBranches.length}',
                    ),
                    _StatChip(
                      label: 'tag',
                      value: '${snapshot.tags.length}',
                    ),
                    _StatChip(
                      label: 'commit',
                      value: snapshot.commitsTruncated
                          ? '${snapshot.commits.length}+'
                          : '${snapshot.commits.length}',
                    ),
                    _StatChip(
                      label: 'alteração',
                      value: '${snapshot.worktree.length}',
                    ),
                    _StatChip(
                      label: 'stash',
                      value: '${snapshot.stashCount}',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('git-refresh-button'),
                    onPressed: refreshing ? null : onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('Atualizar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _short(String? oid) =>
      oid == null ? 'n/d' : oid.substring(0, 7);
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: ink,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: 'JetBrains Mono',
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _GitLoadingView extends StatelessWidget {
  const _GitLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: ocean),
          ),
          SizedBox(height: 14),
          Text(
            'Carregando repositório...',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _GitHint extends StatelessWidget {
  const _GitHint({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function()? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: line),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: muted,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const Key('git-refresh-button'),
                onPressed: action,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Tentar novamente'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
