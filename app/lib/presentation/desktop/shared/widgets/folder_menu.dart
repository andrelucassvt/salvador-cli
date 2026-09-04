import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/workspace_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/workspace_state.dart';

class FolderMenu extends StatelessWidget {
  const FolderMenu({
    super.key,
    required this.state,
    required this.cubit,
    this.maxWidth = 240,
  });

  final WorkspaceReady state;
  final WorkspaceCubit cubit;
  final double maxWidth;

  String get _shortPath {
    final root = state.root;
    if (root == null) return 'Nenhum projeto';
    final parts = root.path
        .split(RegExp(r'[/\\]'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length <= 2) return root.path;
    return '…/${parts.sublist(parts.length - 2).join('/')}';
  }

  @override
  Widget build(BuildContext context) {
    final recents = state.recentRoots;
    return MenuAnchor(
      menuChildren: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Text(
                  'Pasta do projeto',
                  style: TextStyle(
                    color: ink.withValues(alpha: .55),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ...recents.map(
                (path) => _FolderMenuItem(
                  path: path,
                  active: path == state.root?.path,
                  onTap: () => cubit.selectRoot(path),
                ),
              ),
              if (recents.isNotEmpty) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                child: MenuItemButton(
                  onPressed: () async {
                    final selected = await getDirectoryPath(
                      initialDirectory: state.root?.path,
                      confirmButtonText: 'Usar esta pasta',
                    );
                    if (selected != null) await cubit.selectRoot(selected);
                  },
                  leadingIcon: const Icon(
                    Icons.folder_open_rounded,
                    size: 18,
                    color: ocean,
                  ),
                  child: const Text('Escolher outra pasta…'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                child: MenuItemButton(
                  key: const Key('clear-project-menu-item'),
                  onPressed: state.root == null ? null : cubit.clearRoot,
                  leadingIcon: const Icon(
                    Icons.link_off_rounded,
                    size: 18,
                    color: muted,
                  ),
                  child: const Text('Nenhum projeto'),
                ),
              ),
            ],
          ),
        ),
      ],
      builder: (context, menuController, _) => InkWell(
        key: const Key('folder-menu'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => menuController.isOpen
            ? menuController.close()
            : menuController.open(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_outlined, size: 16, color: muted),
              const SizedBox(width: 6),
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Text(
                    _shortPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ink,
                      fontSize: 12,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 3),
              const Icon(Icons.arrow_drop_down_rounded, size: 17, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderMenuItem extends StatelessWidget {
  const _FolderMenuItem({
    required this.path,
    required this.active,
    required this.onTap,
  });

  final String path;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            Icon(
              active
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 15,
              color: active ? ocean : line,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'JetBrains Mono',
                  color: active ? ink : muted,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
