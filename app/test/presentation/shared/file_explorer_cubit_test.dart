import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/domain/entities/workspace_tree_entry_entity.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/file_explorer_cubit.dart';
import 'package:salvador_desktop/presentation/desktop/shared/view_model/file_explorer_state.dart';

import 'fakes/fake_workspace_repository.dart';

void main() {
  late FakeWorkspaceRepository fakeRepository;
  final root = Directory.systemTemp;

  setUp(() {
    fakeRepository = FakeWorkspaceRepository();
  });

  group('FileExplorerCubit.setRoot', () {
    blocTest<FileExplorerCubit, FileExplorerState>(
      'setRoot_whenHierarchical_showsOnlyTopLevelUntilExpanded',
      build: () => FileExplorerCubit(fakeRepository),
      act: (cubit) {
        fakeRepository.tree = const [
          WorkspaceTreeEntryEntity(path: 'src', depth: 0, isDirectory: true),
          WorkspaceTreeEntryEntity(
            path: 'src/main.dart',
            depth: 1,
            isDirectory: false,
          ),
          WorkspaceTreeEntryEntity(
            path: 'README.md',
            depth: 0,
            isDirectory: false,
          ),
        ];
        return cubit.setRoot(root);
      },
      expect: () => [
        isA<FileExplorerLoaded>().having(
          (s) => s.treeEntries.map((e) => e.path),
          'visible paths',
          ['src', 'README.md'],
        ),
      ],
    );

    blocTest<FileExplorerCubit, FileExplorerState>(
      'setRoot_withNull_clearsTreeWithoutCallingRepository',
      build: () => FileExplorerCubit(fakeRepository),
      act: (cubit) async {
        fakeRepository.tree = const [
          WorkspaceTreeEntryEntity(path: 'src', depth: 0, isDirectory: true),
        ];
        await cubit.setRoot(root);
        fakeRepository.listTreeCallCount = 0;
        await cubit.setRoot(null);
      },
      skip: 1,
      expect: () => [
        isA<FileExplorerLoaded>().having(
          (s) => s.treeEntries,
          'treeEntries',
          isEmpty,
        ),
      ],
      verify: (_) => expect(fakeRepository.listTreeCallCount, 0),
    );
  });

  group('FileExplorerCubit.toggleDirectory', () {
    blocTest<FileExplorerCubit, FileExplorerState>(
      'toggleDirectory_whenExpanded_revealsChildren',
      build: () => FileExplorerCubit(fakeRepository),
      seed: () => const FileExplorerLoaded(),
      act: (cubit) async {
        fakeRepository.tree = const [
          WorkspaceTreeEntryEntity(path: 'src', depth: 0, isDirectory: true),
          WorkspaceTreeEntryEntity(
            path: 'src/main.dart',
            depth: 1,
            isDirectory: false,
          ),
        ];
        await cubit.setRoot(root);
        cubit.toggleDirectory('src');
      },
      skip: 1,
      expect: () => [
        isA<FileExplorerLoaded>().having(
          (s) => s.treeEntries.map((e) => e.path),
          'visible paths',
          ['src', 'src/main.dart'],
        ),
      ],
    );
  });

  group('FileExplorerCubit.setFileFilter', () {
    blocTest<FileExplorerCubit, FileExplorerState>(
      'setFileFilter_whenNotEmpty_flattensTreeToMatches',
      build: () => FileExplorerCubit(fakeRepository),
      act: (cubit) async {
        fakeRepository.tree = const [
          WorkspaceTreeEntryEntity(path: 'src', depth: 0, isDirectory: true),
          WorkspaceTreeEntryEntity(
            path: 'src/main.dart',
            depth: 1,
            isDirectory: false,
          ),
          WorkspaceTreeEntryEntity(
            path: 'README.md',
            depth: 0,
            isDirectory: false,
          ),
        ];
        await cubit.setRoot(root);
        cubit.setFileFilter('main');
      },
      skip: 1,
      expect: () => [
        isA<FileExplorerLoaded>().having(
          (s) => s.treeEntries.map((e) => e.path),
          'visible paths',
          ['src', 'src/main.dart'],
        ),
      ],
    );
  });

  group('FileExplorerCubit.openPreview', () {
    blocTest<FileExplorerCubit, FileExplorerState>(
      'openPreview_whenRepositoryFails_setsPreviewErrorWithoutPreview',
      build: () => FileExplorerCubit(fakeRepository),
      act: (cubit) async {
        await cubit.setRoot(root);
        fakeRepository.readFileFailure = const FileSystemFailureException(
          'ERRO: arquivo nao encontrado: x.dart',
        );
        await cubit.openPreview('x.dart');
      },
      skip: 1,
      expect: () => [
        isA<FileExplorerLoaded>()
            .having((s) => s.preview, 'preview', isNull)
            .having((s) => s.previewError, 'previewError', isNotNull),
      ],
    );

    blocTest<FileExplorerCubit, FileExplorerState>(
      'openPreview_whenRepositorySucceeds_setsPreview',
      build: () => FileExplorerCubit(fakeRepository),
      act: (cubit) async {
        await cubit.setRoot(root);
        await cubit.openPreview('a.dart');
      },
      skip: 1,
      expect: () => [
        isA<FileExplorerLoaded>()
            .having((s) => s.preview, 'preview', isNotNull)
            .having((s) => s.previewError, 'previewError', isNull),
      ],
    );
  });

  test('sugere e insere skill pelo prefixo de barra', () async {
    fakeRepository.skillSuggestionsToReturn = const ['/flow'];
    fakeRepository.insertSkillResult = '/flow ';
    final cubit = FileExplorerCubit(fakeRepository);
    addTearDown(cubit.close);
    await cubit.setRoot(root);

    expect(cubit.skillSuggestions('/flo', 4), ['/flow']);
    expect(cubit.insertSkill('/flo', 4, 'flow'), '/flow ');
  });
}
