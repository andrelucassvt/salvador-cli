import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:salvador_desktop/common/utils/formatters.dart';
import 'package:salvador_desktop/domain/entities/workspace_tree_entry_entity.dart';
import 'package:salvador_desktop/presentation/desktop/theme/desktop_theme.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/file_explorer_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/file_explorer_state.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/workspace_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/view_model/workspace_state.dart';

class FilesPanel extends StatelessWidget {
  const FilesPanel({
    super.key,
    required this.filterController,
    required this.onCollapse,
  });

  final TextEditingController filterController;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final fileExplorerCubit = context.read<FileExplorerCubit>();
    return BlocBuilder<FileExplorerCubit, FileExplorerState>(
      builder: (context, state) {
        final loaded = state as FileExplorerLoaded;
        return Container(
          key: const Key('files-panel'),
          decoration: const BoxDecoration(
            color: shell,
            border: Border(left: BorderSide(color: line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 6),
                child: Row(
                  children: [
                    const Text(
                      'ARQUIVOS',
                      style: TextStyle(
                        color: muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7F2F3),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '${loaded.treeEntries.length}',
                        style: const TextStyle(
                          color: ocean,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      key: const Key('collapse-files-panel-button'),
                      tooltip: 'Recolher painel de arquivos',
                      onPressed: onCollapse,
                      icon: const Icon(
                        Icons.menu_open_rounded,
                        color: muted,
                        size: 19,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: TextField(
                  key: const Key('file-filter-field'),
                  controller: filterController,
                  onChanged: fileExplorerCubit.setFileFilter,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'JetBrains Mono',
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Filtrar arquivos…',
                    prefixIcon: Icon(Icons.search_rounded, size: 17),
                    isDense: true,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: loaded.treeEntries.isEmpty
                    ? const Center(
                        child: Text(
                          'Nenhum arquivo corresponde ao filtro.',
                          style: TextStyle(color: muted, fontSize: 11),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: loaded.treeEntries.length,
                        itemBuilder: (context, index) => _TreeRow(
                          entry: loaded.treeEntries[index],
                          onToggleDirectory: fileExplorerCubit.toggleDirectory,
                          onOpenFile: fileExplorerCubit.openPreview,
                        ),
                      ),
              ),
              const Divider(height: 1),
              BlocBuilder<WorkspaceCubit, WorkspaceState>(
                builder: (context, workspaceState) {
                  final rootPath = workspaceState is WorkspaceReady
                      ? workspaceState.root.path
                      : '';
                  return Padding(
                    key: const Key('files-scope-footer'),
                    padding: const EdgeInsets.fromLTRB(14, 9, 14, 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          size: 13,
                          color: muted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            rootPath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: muted,
                              fontSize: 10,
                              fontFamily: 'JetBrains Mono',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.entry,
    required this.onToggleDirectory,
    required this.onOpenFile,
  });

  final WorkspaceTreeEntryEntity entry;
  final ValueChanged<String> onToggleDirectory;
  final Future<void> Function(String path) onOpenFile;

  @override
  Widget build(BuildContext context) {
    final indent = 10.0 + entry.depth * 14.0;
    return InkWell(
      key: Key('tree-entry-${entry.path}'),
      onTap: () => entry.isDirectory
          ? onToggleDirectory(entry.path)
          : onOpenFile(entry.path),
      child: Container(
        padding: EdgeInsets.fromLTRB(indent, 6, 12, 6),
        color: entry.selected ? const Color(0xFFE7F2F3) : Colors.transparent,
        child: Row(
          children: [
            Icon(
              entry.isDirectory
                  ? entry.expanded
                        ? Icons.folder_open_rounded
                        : Icons.folder_rounded
                  : Icons.description_outlined,
              size: 15,
              color: entry.isDirectory ? ocean : muted,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                entry.path.split('/').last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: entry.selected ? ocean : ink,
                  fontSize: 11.5,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: entry.isDirectory || entry.selected
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ),
            if (!entry.isDirectory) ...[
              const SizedBox(width: 6),
              Text(
                formatBytes(entry.sizeBytes),
                style: const TextStyle(
                  color: muted,
                  fontSize: 9,
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

class FilesRail extends StatelessWidget {
  const FilesRail({super.key, required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('files-rail'),
      decoration: const BoxDecoration(
        color: shell,
        border: Border(left: BorderSide(color: line)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          IconButton(
            key: const Key('right-rail-files-button'),
            tooltip: 'Arquivos',
            onPressed: onExpand,
            icon: const Icon(Icons.folder_outlined, color: muted, size: 18),
          ),
        ],
      ),
    );
  }
}
