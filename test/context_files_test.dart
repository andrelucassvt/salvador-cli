import 'dart:io';

import 'package:salvador_cli/salvador_cli.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;

  Future<void> writeSkill(String name, String content) async {
    final file = File('${root.path}/.agents/skills/$name/SKILL.md');
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('leve_context_files_test_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('descobre somente skills validas e le suas descricoes', () async {
    await writeSkill('a', '---\ndescription: Skill A\n---\n# A');
    await writeSkill('b', '---\ndescription: Skill B\n---\n# B');
    await writeSkill('sem-descricao', '# Skill sem frontmatter');
    await Directory(
      '${root.path}/.agents/skills/sem-arquivo',
    ).create(recursive: true);
    await File('${root.path}/.agents/solto.md').writeAsString('ignorar');

    final skills = ContextFilesService(root).discoverSkills();

    expect(
      skills,
      containsAll([
        const SkillInfo(name: 'a', description: 'Skill A'),
        const SkillInfo(name: 'b', description: 'Skill B'),
        const SkillInfo(name: 'sem-descricao', description: ''),
      ]),
    );
    expect(skills, hasLength(3));
  });

  test('sem pasta de skills devolve uma lista vazia', () {
    expect(ContextFilesService(root).discoverSkills(), isEmpty);
  });

  test('anexa AGENTS.md valido com rotulo de contexto do projeto', () async {
    await File('${root.path}/AGENTS.md').writeAsString('Use testes primeiro.');

    final context = ContextFilesService(root).agentsMdContext();

    expect(context, isNotNull);
    expect(context, contains('Contexto do projeto (AGENTS.md)'));
    expect(context, contains('Use testes primeiro.'));
  });

  test('ignora AGENTS.md ausente, grande, binario ou UTF-8 invalido', () async {
    final service = ContextFilesService(root);
    expect(service.agentsMdContext(), isNull);

    final agents = File('${root.path}/AGENTS.md');
    await agents.writeAsString('x' * (64 * 1024 + 1));
    expect(service.agentsMdContext(), isNull);

    await agents.writeAsBytes([0x41, 0x00]);
    expect(service.agentsMdContext(), isNull);

    await agents.writeAsBytes([0xC3, 0x28]);
    expect(service.agentsMdContext(), isNull);
  });

  test('expande skills mencionadas no prompt e preserva o texto', () async {
    await writeSkill('flow', '# Flow\nUse para mapear fluxos.');
    await writeSkill('teste', '# Teste\nUse para testar.');
    final service = ContextFilesService(root);

    final expansion = service.expand('/flow como funciona o login /teste');

    expect(expansion.prompt, startsWith('/flow como funciona o login /teste'));
    expect(expansion.prompt, contains('Use o conteudo abaixo como contexto'));
    expect(expansion.prompt, contains('Use para mapear fluxos.'));
    expect(expansion.prompt, contains('Use para testar.'));
    expect(expansion.files, ['flow', 'teste']);
    expect(expansion.warnings, isEmpty);
  });

  test('mantem o prompt e avisa para skill inexistente', () {
    final expansion = ContextFilesService(root).expand('/naoexiste explique');

    expect(expansion.prompt, '/naoexiste explique');
    expect(expansion.warnings.single, contains('skill nao encontrada'));
  });

  test('nao expande barra isolada ou texto sem prefixo de skill', () {
    final service = ContextFilesService(root);

    expect(service.expand('/').prompt, '/');
    expect(service.expand('explique o login').prompt, 'explique o login');
  });

  test(
    'le skill conhecida, rejeita caminho invalido e trunca conteudo',
    () async {
      await writeSkill('flow', '# Flow');
      await writeSkill('grande', 'x' * (64 * 1024 + 1));
      final service = ContextFilesService(root);

      expect(service.skillContent('flow'), '# Flow');
      expect(service.skillContent('inexistente'), isNull);
      expect(service.skillContent('../flow'), isNull);
      expect(service.skillContent('grande'), endsWith('[TRUNCADO]'));
    },
  );

  test('a tool use_skill le conteudo e lista skills em erros', () async {
    await writeSkill('flow', '# Flow');
    final registry = ToolRegistry(
      root,
      contextFiles: ContextFilesService(root),
    );

    expect(
      registry.definitions.map((tool) => tool.name),
      contains('use_skill'),
    );
    expect(
      await registry.execute(
        ToolCall(name: 'use_skill', arguments: {'name': 'flow'}),
      ),
      '# Flow',
    );
    expect(
      await registry.execute(
        ToolCall(name: 'use_skill', arguments: {'name': 'ausente'}),
      ),
      contains('skill nao encontrada: ausente. Skills disponiveis: flow'),
    );
    expect(
      await registry.execute(ToolCall(name: 'use_skill', arguments: {})),
      contains('argumento "name"'),
    );
  });

  test('sem servico de contexto use_skill continua desconhecida', () async {
    final result = await ToolRegistry(
      root,
    ).execute(ToolCall(name: 'use_skill', arguments: {'name': 'flow'}));

    expect(result, 'ERRO: ferramenta desconhecida: use_skill');
  });
}
