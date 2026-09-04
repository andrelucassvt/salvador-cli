import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_state.dart';

/// Alteracoes locais agrupadas por staged, unstaged, untracked e conflicted.
/// Grupos vazios nao aparecem; selecao de arquivo mostra o resumo no
/// inspector.
class GitWorktreePanel extends StatelessWidget {
  const GitWorktreePanel({super.key, this.onOpenFile});

  final Future<void> Function(String path)? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GitCubit>();
    return BlocBuilder<GitCubit, GitState>(
      builder: (context, state) {
        if (state is! GitLoaded) return const SizedBox.shrink();
        final entries = state.visibleWorktree;
        return Container(
          key: const Key('git-worktree-panel'),
          height: 188,
          decoration: const BoxDecoration(
            color: gitToolbarSurface,
            border: Border(top: BorderSide(color: line)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text(
                    'Mesa de trabalho',
                    style: TextStyle(
                      color: ink,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${entries.length}',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 9.5,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                  const Spacer(),
                  if (state.searchQuery.isNotEmpty)
                    Text(
                      'filtro: "${state.searchQuery}"',
                      style: const TextStyle(color: muted, fontSize: 9.5),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: entries.isEmpty
                    ? const Center(
                        child: Text(
                          'Sem alterações locais.',
                          style: TextStyle(color: muted, fontSize: 11),
                        ),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final group in [
                            (
                              name: 'staged',
                              label: 'PREPARADAS',
                              entries: entries
                                  .where(
                                    (entry) =>
                                        entry.status ==
                                        GitWorktreeStatus.staged,
                                  )
                                  .toList(),
                            ),
                            (
                              name: 'unstaged',
                              label: 'NÃO PREPARADAS',
                              entries: entries
                                  .where(
                                    (entry) =>
                                        entry.status ==
                                        GitWorktreeStatus.unstaged,
                                  )
                                  .toList(),
                            ),
                            (
                              name: 'untracked',
                              label: 'NOVOS',
                              entries: entries
                                  .where(
                                    (entry) =>
                                        entry.status ==
                                        GitWorktreeStatus.untracked,
                                  )
                                  .toList(),
                            ),
                            (
                              name: 'conflicted',
                              label: 'CONFLITOS',
                              entries: entries
                                  .where(
                                    (entry) =>
                                        entry.status ==
                                        GitWorktreeStatus.conflicted,
                                  )
                                  .toList(),
                            ),
                          ])
                            if (group.entries.isNotEmpty) ...[
                              Expanded(
                                child: _WorktreeGroup(
                                  keyName: group.name,
                                  label: group.label,
                                  entries: group.entries,
                                  selectedPath: state.selectedFilePath,
                                  onTap: cubit.selectFile,
                                  onOpenFile: onOpenFile,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WorktreeGroup extends StatelessWidget {
  const _WorktreeGroup({
    required this.keyName,
    required this.label,
    required this.entries,
    required this.selectedPath,
    required this.onTap,
    this.onOpenFile,
  });

  final String keyName;
  final String label;
  final List<GitWorktreeEntry> entries;
  final String? selectedPath;
  final ValueChanged<String> onTap;
  final Future<void> Function(String path)? onOpenFile;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('git-worktree-group-$keyName'),
      decoration: BoxDecoration(
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 6, 9, 4),
            child: Text(
              '$label (${entries.length})',
              style: const TextStyle(
                color: muted,
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 4),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final selected = entry.path == selectedPath;
                return InkWell(
                  key: Key('git-file-${entry.path}'),
                  onTap: () {
                    onTap(entry.path);
                    onOpenFile?.call(entry.path);
                  },
                  child: Container(
                    color: selected ? gitSelectedColor : null,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _iconFor(entry.status),
                          size: 12,
                          color: _colorFor(entry.status),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            entry.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected ? ocean : ink,
                              fontSize: 10,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              fontFamily: 'JetBrains Mono',
                            ),
                          ),
                        ),
                        if (entry.origPath != null)
                          Tooltip(
                            message: 'renomeado de ${entry.origPath}',
                            child: const Icon(
                              Icons.drive_file_move_outlined,
                              size: 11,
                              color: muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(GitWorktreeStatus status) => switch (status) {
    GitWorktreeStatus.staged => Icons.add_box_outlined,
    GitWorktreeStatus.unstaged => Icons.edit_outlined,
    GitWorktreeStatus.untracked => Icons.add_circle_outline_rounded,
    GitWorktreeStatus.conflicted => Icons.error_outline_rounded,
  };

  static Color _colorFor(GitWorktreeStatus status) => switch (status) {
    GitWorktreeStatus.staged => const Color(0xFF2E7D57),
    GitWorktreeStatus.unstaged => const Color(0xFF147D92),
    GitWorktreeStatus.untracked => const Color(0xFF8A5CF6),
    GitWorktreeStatus.conflicted => const Color(0xFFB3492E),
  };
}
