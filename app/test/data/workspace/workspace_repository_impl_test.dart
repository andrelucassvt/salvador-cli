import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_desktop/config/error/app_exception.dart';
import 'package:salvador_desktop/data/repositories/workspace_repository_impl.dart';
import 'package:salvador_desktop/domain/entities/workspace_tree_entry_entity.dart';

import 'fakes/fake_workspace_datasource.dart';

void main() {
  late FakeWorkspaceDataSource fakeDataSource;
  late WorkspaceRepositoryImpl repository;
  final root = Directory.systemTemp;

  setUp(() {
    fakeDataSource = FakeWorkspaceDataSource();
    repository = WorkspaceRepositoryImpl(fakeDataSource);
  });

  group('WorkspaceRepositoryImpl.listTree', () {
    test('listTree_whenDataSourceSucceeds_returnsOk', () async {
      fakeDataSource.tree = const [
        WorkspaceTreeEntryEntity(path: 'a.dart', depth: 0, isDirectory: false),
      ];

      final result = await repository.listTree(root: root);

      result.when(
        ok: (entries) => expect(entries, hasLength(1)),
        error: (_) => fail('esperava sucesso'),
      );
    });
  });

  group('WorkspaceRepositoryImpl.readFile', () {
    test('readFile_whenContentReturned_returnsOkWithPreview', () async {
      fakeDataSource.readFileResult = 'linha1\nlinha2';

      final result = await repository.readFile(root: root, path: 'a.dart');

      result.when(
        ok: (preview) {
          expect(preview.path, 'a.dart');
          expect(preview.lineCount, 2);
          expect(preview.language, 'dart');
        },
        error: (_) => fail('esperava sucesso'),
      );
    });

    test(
      'readFile_whenToolRegistryReturnsErro_returnsFileSystemFailureException',
      () async {
        fakeDataSource.readFileResult = 'ERRO: arquivo nao encontrado: x.dart';

        final result = await repository.readFile(root: root, path: 'x.dart');

        result.when(
          ok: (_) => fail('esperava erro'),
          error: (error) => expect(error, isA<FileSystemFailureException>()),
        );
      },
    );
  });
}
