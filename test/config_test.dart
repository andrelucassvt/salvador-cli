import 'package:salvador_cli/salvador_cli.dart';
import 'package:test/test.dart';

void main() {
  test('contexto de arquivos fica habilitado por padrao', () {
    expect(CliConfig.parse([]).contextFiles, isTrue);
  });

  test('desabilita contexto de arquivos com --no-context', () {
    expect(CliConfig.parse(['--no-context']).contextFiles, isFalse);
  });

  test('documenta a flag --no-context na ajuda', () {
    expect(cliUsage, contains('--no-context'));
  });
}
