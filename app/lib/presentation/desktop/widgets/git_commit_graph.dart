import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/git_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/git_state.dart';
import 'package:salvador_desktop/presentation/desktop/widgets/git_graph_layout.dart';
import 'package:salvador_desktop/presentation/desktop/widgets/git_graph_painter.dart';

/// Lista virtualizada de commits com grafo desenhado por linha. Cada linha
/// tem `RepaintBoundary`, `InkWell` e `Semantics`; o canvas so desenha as
/// conexoes da fatia, sem hit testing.
class GitCommitGraph extends StatelessWidget {
  const GitCommitGraph({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GitCubit>();
    return BlocBuilder<GitCubit, GitState>(
      builder: (context, state) {
        if (state is! GitLoaded) return const SizedBox.shrink();
        final commits = state.visibleCommits;
        final layout = GitGraphLayout.calculate(commits);
        final footerCount = (state.loadingMore || state.hasMoreCommits) ? 1 : 0;
        return ListView.builder(
          key: const Key('git-commit-graph'),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: commits.length + footerCount,
          itemBuilder: (context, index) {
            if (index == commits.length) {
              return _GraphFooter(
                loading: state.loadingMore,
                onLoadMore: cubit.loadMore,
              );
            }
            final commit = commits[index];
            final refs = _refsFor(state.snapshot, commit.hash);
            return RepaintBoundary(
              child: InkWell(
                key: Key('git-commit-row-${commit.shortHash}'),
                onTap: () => cubit.selectCommit(commit.hash),
                child: Semantics(
                  selected: state.selectedCommitHash == commit.hash,
                  button: true,
                  label: '${commit.subject}, ${commit.shortHash}',
                  child: Container(
                    height: gitRowHeight,
                    color: state.selectedCommitHash == commit.hash
                        ? gitSelectedColor
                        : null,
                    child: Row(
                      children: [
                        CustomPaint(
                          size: Size(
                            layout.laneCount * gitLaneWidth,
                            gitRowHeight,
                          ),
                          painter: GitGraphPainter(
                            layout: layout,
                            row: index,
                            laneWidth: gitLaneWidth,
                            rowHeight: gitRowHeight,
                            nodeRadius: 4.5,
                            laneColor: gitLaneColor,
                            mergeColor: gitMergeColor,
                            nodeColor: gitNodeColor,
                            headColor: gitHeadColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          commit.shortHash,
                          style: const TextStyle(
                            color: muted,
                            fontSize: 10.5,
                            fontFamily: 'JetBrains Mono',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            commit.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ink,
                              fontSize: 12.5,
                              fontWeight:
                                  state.selectedCommitHash == commit.hash
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (refs.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              refs,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: ocean,
                                fontSize: 9.5,
                                fontFamily: 'JetBrains Mono',
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 12),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static String _refsFor(GitSnapshot snapshot, String hash) {
    final names = <String>[
      for (final ref in [
        ...snapshot.localBranches,
        ...snapshot.remoteBranches,
        ...snapshot.tags,
      ])
        if (ref.hash == hash) ref.shortName,
    ];
    return names.join(' · ');
  }
}

class _GraphFooter extends StatelessWidget {
  const _GraphFooter({required this.loading, required this.onLoadMore});

  final bool loading;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 44,
        child: Center(
          child: SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return SizedBox(
      height: 44,
      child: Center(
        child: OutlinedButton(
          key: const Key('git-load-more-button'),
          onPressed: onLoadMore,
          child: const Text('Carregar mais'),
        ),
      ),
    );
  }
}
