import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/git/view_model/git_state.dart';

/// Navegador de refs: busca, grupos Atual/Locais/Remotas/Tags/Stashes
/// recolhiveis e selecao de ref.
class GitBranchesPanel extends StatelessWidget {
  const GitBranchesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GitCubit>();
    return BlocBuilder<GitCubit, GitState>(
      builder: (context, state) {
        if (state is! GitLoaded) return const SizedBox.shrink();
        return Container(
          key: const Key('git-branches-panel'),
          width: 228,
          decoration: const BoxDecoration(
            color: paper,
            border: Border(right: BorderSide(color: line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: TextField(
                  key: const Key('git-branch-search'),
                  onChanged: cubit.search,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Pesquisar refs…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 16),
                    prefixIconConstraints: const BoxConstraints(minWidth: 30),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    if (state.snapshot.repository.branch != null)
                      _BranchGroup(
                        name: 'Atual',
                        keyName: 'atual',
                        count: 1,
                        expanded: true,
                        children: [
                          _CurrentBranchTile(
                            snapshot: state.snapshot,
                            cubit: cubit,
                          ),
                        ],
                      ),
                    _BranchGroup(
                      name: 'Locais',
                      keyName: 'locais',
                      count: state.visibleLocalBranches.length,
                      children: state.visibleLocalBranches
                          .map(
                            (ref) => _RefTile(
                              ref: ref,
                              selected: state.selectedRef == ref.name,
                              onTap: () => cubit.selectRef(ref.name),
                            ),
                          )
                          .toList(growable: false),
                    ),
                    _BranchGroup(
                      name: 'Remotas',
                      keyName: 'remotas',
                      count: state.visibleRemoteBranches.length,
                      children: state.visibleRemoteBranches
                          .map(
                            (ref) => _RefTile(
                              ref: ref,
                              selected: state.selectedRef == ref.name,
                              onTap: () => cubit.selectRef(ref.name),
                            ),
                          )
                          .toList(growable: false),
                    ),
                    _BranchGroup(
                      name: 'Tags',
                      keyName: 'tags',
                      count: state.visibleTags.length,
                      children: state.visibleTags
                          .map(
                            (ref) => _RefTile(
                              ref: ref,
                              selected: state.selectedRef == ref.name,
                              onTap: () => cubit.selectRef(ref.name),
                            ),
                          )
                          .toList(growable: false),
                    ),
                    if (state.snapshot.stashCount > 0)
                      _BranchGroup(
                        name: 'Stashes',
                        keyName: 'stashes',
                        count: state.snapshot.stashCount,
                        children: [
                          for (
                            var index = 0;
                            index < state.snapshot.stashCount;
                            index++
                          )
                            _StashTile(
                              index: index,
                              selected:
                                  state.selectedRef == 'refs/stash@{$index}',
                              onTap: () =>
                                  cubit.selectRef('refs/stash@{$index}'),
                            ),
                        ],
                      ),
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

class _BranchGroup extends StatefulWidget {
  const _BranchGroup({
    required this.name,
    required this.keyName,
    required this.count,
    this.children = const [],
    this.expanded = true,
  });

  final String name;
  final String keyName;
  final int count;
  final List<Widget> children;
  final bool expanded;

  @override
  State<_BranchGroup> createState() => _BranchGroupState();
}

class _BranchGroupState extends State<_BranchGroup> {
  late bool _expanded = widget.expanded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: Key('git-branch-group-${widget.keyName}'),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 6),
            child: Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.expand_more_rounded
                      : Icons.chevron_right_rounded,
                  size: 16,
                  color: muted,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.name,
                    style: const TextStyle(
                      color: muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: line.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${widget.count}',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...widget.children,
      ],
    );
  }
}

class _CurrentBranchTile extends StatelessWidget {
  const _CurrentBranchTile({required this.snapshot, required this.cubit});

  final GitSnapshot snapshot;
  final GitCubit cubit;

  @override
  Widget build(BuildContext context) {
    final branch = snapshot.repository.branch!;
    return InkWell(
      key: const Key('git-current-branch'),
      onTap: () => cubit.selectRef('refs/heads/$branch'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: coral,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                branch,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ink,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
            if (snapshot.upstream != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.call_split_rounded, size: 11, color: muted),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  snapshot.upstream!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 9.5,
                    fontFamily: 'JetBrains Mono',
                  ),
                ),
              ),
            ],
            if (snapshot.ahead > 0 || snapshot.behind > 0) ...[
              const SizedBox(width: 6),
              Text(
                '+${snapshot.ahead} -${snapshot.behind}',
                style: const TextStyle(
                  color: muted,
                  fontSize: 9.5,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RefTile extends StatelessWidget {
  const _RefTile({
    required this.ref,
    required this.selected,
    required this.onTap,
  });

  final GitRef ref;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final remote = ref.name.startsWith('refs/remotes/');
    final tag = ref.name.startsWith('refs/tags/');
    return InkWell(
      key: Key('git-ref-${ref.name}'),
      onTap: onTap,
      child: Container(
        color: selected ? gitSelectedColor : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          children: [
            Icon(
              tag
                  ? Icons.sell_outlined
                  : remote
                  ? Icons.cloud_outlined
                  : Icons.account_tree_outlined,
              size: 13,
              color: selected ? ocean : muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ref.shortName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? ocean : ink,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StashTile extends StatelessWidget {
  const _StashTile({
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('git-stash-$index'),
      onTap: onTap,
      child: Container(
        color: selected ? gitSelectedColor : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          children: [
            const Icon(Icons.bookmark_outline_rounded, size: 13, color: muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'stash@{$index}',
                style: const TextStyle(
                  color: ink,
                  fontSize: 11,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
