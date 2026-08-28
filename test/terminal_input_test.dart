import 'dart:convert';
import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:test/test.dart';

void main() {
  test('completa @arquivo sem perder a digitacao em andamento', () async {
    final root = await Directory.systemTemp.createTemp('leve_input_test_');
    addTearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });
    await Directory('${root.path}/lib').create();
    await File('${root.path}/lib/agent.dart').writeAsString('codigo');
    final output = StringBuffer();
    final bytes = utf8.encode('analise @lib/a\t e continue\r');
    final terminal = TerminalInput(
      input: Stream.value(bytes),
      output: output,
      interactive: true,
    );

    final line = await terminal.readLine(
      prompt: 'voce> ',
      mentions: FileMentionService(root),
    );
    await terminal.close();

    expect(line, 'analise @lib/agent.dart  e continue');
    expect(output.toString(), contains('@lib/agent.dart'));
    expect(output.toString(), contains('analise '));
  });

  test('edita texto com setas sem submeter a linha', () async {
    final output = StringBuffer();
    final bytes = <int>[
      ...utf8.encode('ac'),
      27,
      91,
      68, // seta para esquerda
      ...utf8.encode('b'),
      13,
    ];
    final terminal = TerminalInput(
      input: Stream.value(bytes),
      output: output,
      interactive: true,
    );

    final line = await terminal.readLine(prompt: '> ');
    await terminal.close();

    expect(line, 'abc');
  });

  test('rejeita prompt multilinha para impedir espacos durante redesenho', () {
    final terminal = TerminalInput(
      input: const Stream.empty(),
      output: StringBuffer(),
      interactive: true,
    );
    addTearDown(terminal.close);

    expect(terminal.readLine(prompt: '\nvoce> '), throwsArgumentError);
  });
}
