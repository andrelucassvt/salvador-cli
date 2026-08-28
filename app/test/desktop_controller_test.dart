import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salvador_cli/salvador_cli.dart';
import 'package:salvador_desktop/src/desktop/desktop_controller.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('salvador_desktop_test_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('sugere e insere menção de arquivo com espaços', () async {
    await File(
      '${root.path}/arquivo com espaço.dart',
    ).writeAsString('void main() {}');
    final controller = DesktopController(initialRoot: root);
    const input = 'revise @arquivo';

    final suggestions = controller.fileSuggestions(input, input.length);
    final result = controller.insertMention(
      input,
      input.length,
      suggestions.single,
    );

    expect(suggestions, ['arquivo com espaço.dart']);
    expect(result, 'revise @"arquivo com espaço.dart" ');
    controller.dispose();
  });

  test('resume atividade de ferramenta por caminho ou comando', () {
    final fileActivity = ToolActivity(
      ToolCall(name: 'read_file', arguments: {'path': 'lib/main.dart'}),
    );
    final commandActivity = ToolActivity(
      ToolCall(name: 'run_command', arguments: {'command': 'dart test'}),
    );

    expect(fileActivity.summary, 'lib/main.dart');
    expect(commandActivity.summary, 'dart test');
  });
}
