import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/common/services/desktop_storage_service.dart';
import 'package:salvador_desktop/domain/entities/desktop_preferences_entity.dart';
import 'package:salvador_desktop/domain/entities/persisted_session_summary_entity.dart';

void main() {
  late Directory tempDir;
  late File stateFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('salvador_store_test_');
    stateFile = File('${tempDir.path}/state.json');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test(
    'round-trip de preferencias, parametros, permissoes e pasta ativa',
    () async {
      final store = DesktopStorageService(file: stateFile);
      final state = DesktopPreferencesEntity(
        host: Uri.parse('http://192.168.0.10:11434'),
        model: 'llama3.2:3b',
        inference: InferenceOptions(
          temperature: 0.4,
          contextLength: 4096,
          keepAlive: Duration(minutes: 30),
          timeout: Duration(seconds: 45),
        ),
        permissions: const AgentPermissions(
          allowEdit: false,
          allowCommands: true,
        ),
        activeRoot: '/projetos/salvador',
        recentRoots: ['/projetos/salvador', '/projetos/outro'],
        sessions: [
          PersistedSessionSummaryEntity(
            title: 'Primeira sessao',
            startedAt: DateTime(2026, 8, 20, 10, 30),
            actionCount: 5,
          ),
        ],
      );

      await store.save(state);
      final restored = await DesktopStorageService(file: stateFile).load();

      expect(restored.host, state.host);
      expect(restored.model, state.model);
      expect(restored.inference.temperature, 0.4);
      expect(restored.inference.contextLength, 4096);
      expect(restored.inference.keepAlive, const Duration(minutes: 30));
      expect(restored.inference.timeout, const Duration(seconds: 45));
      expect(restored.permissions.allowEdit, isFalse);
      expect(restored.permissions.allowCommands, isTrue);
      expect(restored.activeRoot, '/projetos/salvador');
      expect(restored.recentRoots, ['/projetos/salvador', '/projetos/outro']);
      expect(restored.sessions, hasLength(1));
      expect(restored.sessions.single.title, 'Primeira sessao');
      expect(restored.sessions.single.actionCount, 5);
      expect(restored.sessions.single.startedAt.year, 2026);
    },
  );

  test('deduplica pastas recentes e retem os resumos mais novos', () async {
    final store = DesktopStorageService(file: stateFile);
    final oldest = DateTime(2026, 1, 1);
    final state = DesktopPreferencesEntity(
      recentRoots: ['/b', '/a', '/b', '/a'],
      sessions: [
        for (var i = 0; i < 25; i++)
          PersistedSessionSummaryEntity(
            title: 'sessao $i',
            startedAt: oldest.add(Duration(days: i)),
            actionCount: i,
          ),
      ],
    );

    await store.save(state);
    final restored = await DesktopStorageService(file: stateFile).load();

    expect(restored.recentRoots, ['/b', '/a']);
    expect(restored.sessions, hasLength(20));
    expect(restored.sessions.first.title, 'sessao 24');
    expect(restored.sessions.last.title, 'sessao 5');
  });

  test('retorna defaults para arquivo inexistente', () async {
    final state = await DesktopStorageService(file: stateFile).load();

    expect(state.host, isNull);
    expect(state.model, isNull);
    expect(state.inference.temperature, 0.1);
    expect(state.inference.contextLength, isNull);
    expect(state.permissions.allowEdit, isTrue);
    expect(state.permissions.allowCommands, isTrue);
    expect(state.activeRoot, isNull);
    expect(state.recentRoots, isEmpty);
    expect(state.sessions, isEmpty);
  });

  test('retorna defaults para JSON corrompido', () async {
    await stateFile.writeAsString('{nao e json');

    final state = await DesktopStorageService(file: stateFile).load();

    expect(state.host, isNull);
    expect(state.model, isNull);
    expect(state.recentRoots, isEmpty);
  });

  test('retorna defaults para versao desconhecida', () async {
    await stateFile.writeAsString(jsonEncode({'version': 999, 'model': 'x'}));

    final state = await DesktopStorageService(file: stateFile).load();

    expect(state.model, isNull);
    expect(state.recentRoots, isEmpty);
  });

  test('tolera campos opcionais ausentes em arquivo valido', () async {
    await stateFile.writeAsString(
      jsonEncode({'version': 1, 'model': 'gemma2:2b'}),
    );

    final state = await DesktopStorageService(file: stateFile).load();

    expect(state.model, 'gemma2:2b');
    expect(state.host, isNull);
    expect(state.activeRoot, isNull);
    expect(state.recentRoots, isEmpty);
    expect(state.sessions, isEmpty);
    expect(state.inference.temperature, 0.1);
    expect(state.permissions.allowEdit, isTrue);
  });

  test('grava arquivo valido sem deixar temporario no diretorio', () async {
    final store = DesktopStorageService(file: stateFile);

    await store.save(DesktopPreferencesEntity(model: 'llama3.2:3b'));

    expect(stateFile.existsSync(), isTrue);
    final decoded = jsonDecode(stateFile.readAsStringSync());
    expect(decoded['model'], 'llama3.2:3b');
    expect(decoded['version'], 1);
    expect(File('${stateFile.path}.tmp').existsSync(), isFalse);
  });

  test('substitui o arquivo anterior por completo', () async {
    final store = DesktopStorageService(file: stateFile);

    await store.save(
      DesktopPreferencesEntity(model: 'primeiro', recentRoots: ['/um']),
    );
    await store.save(DesktopPreferencesEntity(model: 'segundo'));

    final state = await store.load();
    expect(state.model, 'segundo');
    expect(state.recentRoots, isEmpty);
  });
}
