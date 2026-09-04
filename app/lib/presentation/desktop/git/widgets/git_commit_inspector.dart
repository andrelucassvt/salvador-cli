import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_state.dart';

/// Detalhes do commit selecionado (ou do arquivo selecionado no worktree):
/// hash copiavel, autor/data, mensagem, pais, refs e arquivos alterados.
class GitCommitInspector extends StatelessWidget {
  const GitCommitInspector({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GitCubit, GitState>(
      builder: (context, state) {
        if (state is! GitLoaded) return const SizedBox.shrink();
        final file = state.selectedFilePath == null
            ? null
            : _worktreeEntry(state, state.selectedFilePath!);
        final commit = file == null ? _commit(state) : null;
        return Container(
          key: const Key('git-commit-inspector'),
          width: 300,
          decoration: const BoxDecoration(
            color: paper,
            border: Border(left: BorderSide(color: line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Text(
                  'DETALHES',
                  style: TextStyle(
                    color: muted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Expanded(
                child: file != null
                    ? _FileSummary(file: file)
                    : commit != null
                    ? _CommitDetails(commit: commit, state: state)
                    : const Center(
                        child: Text(
                          'Selecione um commit para ver os detalhes.',
                          style: TextStyle(color: muted, fontSize: 11.5),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  static GitCommit? _commit(GitLoaded state) {
    final selected = state.selectedCommit;
    if (selected != null) return selected;
    if (state.visibleCommits.isNotEmpty) {
      return state.visibleCommits.first;
    }
    return null;
  }

  static GitWorktreeEntry? _worktreeEntry(GitLoaded state, String path) {
    for (final entry in state.snapshot.worktree) {
      if (entry.path == path) return entry;
    }
    return null;
  }
}

class _CommitDetails extends StatelessWidget {
  const _CommitDetails({required this.commit, required this.state});

  final GitCommit commit;
  final GitLoaded state;

  @override
  Widget build(BuildContext context) {
    final refs = _refsFor(state.snapshot, commit.hash);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            commit.subject,
            style: const TextStyle(
              color: ink,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.commit_rounded, size: 13, color: muted),
              const SizedBox(width: 5),
              Text(
                commit.shortHash,
                style: const TextStyle(
                  color: ocean,
                  fontSize: 11,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const Key('git-copy-hash-button'),
                tooltip: 'Copiar hash',
                visualDensity: VisualDensity.compact,
                iconSize: 14,
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: commit.hash)),
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${commit.authorName} <${commit.authorEmail}>',
            style: const TextStyle(color: muted, fontSize: 10.5),
          ),
          Text(
            _formatDate(commit.authorDate),
            style: const TextStyle(
              color: muted,
              fontSize: 10,
              fontFamily: 'JetBrains Mono',
            ),
          ),
          if (commit.isMerge) ...[
            const SizedBox(height: 4),
            Text(
              'merge de ${commit.parentHashes.length} pais',
              style: const TextStyle(
                color: gitMergeColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (refs.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              refs,
              style: const TextStyle(
                color: ocean,
                fontSize: 10,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ],
          if (commit.body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              commit.bodyTruncated
                  ? '${commit.body}\n[…] mensagem truncada'
                  : commit.body,
              style: const TextStyle(color: ink, fontSize: 11, height: 1.5),
            ),
          ],
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 8),
          Text(
            'ARQUIVOS (${commit.files.length}${commit.filesTruncated ? '+' : ''})',
            style: const TextStyle(
              color: muted,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          if (commit.files.isEmpty)
            const Text(
              'Sem arquivos alterados.',
              style: TextStyle(color: muted, fontSize: 10.5),
            )
          else
            ...commit.files.map(
              (file) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _statusColor(file.status).withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        file.status,
                        style: TextStyle(
                          color: _statusColor(file.status),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        file.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ink,
                          fontSize: 10.5,
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static Color _statusColor(String status) => switch (status) {
    'A' => const Color(0xFF2E7D57),
    'D' => const Color(0xFFB3492E),
    'R' || 'C' => const Color(0xFF8A5CF6),
    _ => const Color(0xFF147D92),
  };
}

class _FileSummary extends StatelessWidget {
  const _FileSummary({required this.file});

  final GitWorktreeEntry file;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.description_outlined, size: 20, color: muted),
          const SizedBox(height: 8),
          Text(
            file.path,
            style: const TextStyle(
              color: ink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'JetBrains Mono',
            ),
          ),
          const SizedBox(height: 10),
          Container(
            key: const Key('git-file-summary'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: gitSelectedColor,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_statusIcon, size: 15, color: _statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusLabel,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'O diff completo aparece no resumo local; o snapshot só expõe '
            'o status por arquivo.',
            style: TextStyle(color: muted, fontSize: 10.5, height: 1.5),
          ),
        ],
      ),
    );
  }

  IconData get _statusIcon => switch (file.status) {
    GitWorktreeStatus.staged => Icons.check_circle_outline_rounded,
    GitWorktreeStatus.unstaged => Icons.edit_outlined,
    GitWorktreeStatus.untracked => Icons.add_circle_outline_rounded,
    GitWorktreeStatus.conflicted => Icons.error_outline_rounded,
  };

  Color get _statusColor => switch (file.status) {
    GitWorktreeStatus.staged => const Color(0xFF2E7D57),
    GitWorktreeStatus.unstaged => const Color(0xFF147D92),
    GitWorktreeStatus.untracked => const Color(0xFF8A5CF6),
    GitWorktreeStatus.conflicted => const Color(0xFFB3492E),
  };

  String get _statusLabel => switch (file.status) {
    GitWorktreeStatus.staged =>
      'Preparado (staged): mudança adicionada ao '
          'index e pronta para o commit.',
    GitWorktreeStatus.unstaged =>
      'Não preparado (unstaged): mudança no '
          'worktree ainda não adicionada ao index.',
    GitWorktreeStatus.untracked =>
      'Novo (untracked): arquivo ainda não '
          'rastreado pelo Git.',
    GitWorktreeStatus.conflicted =>
      'Conflito (conflicted): o merge não '
          'conseguiu resolver este arquivo.',
  };
}

String _refsFor(GitSnapshot snapshot, String hash) {
  final names = <String>[
    for (final ref in [
      ...snapshot.localBranches,
      ...snapshot.remoteBranches,
      ...snapshot.tags,
    ])
      if (ref.hash == hash) ref.shortName,
  ];
  return names.isEmpty ? '' : names.join(' · ');
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
