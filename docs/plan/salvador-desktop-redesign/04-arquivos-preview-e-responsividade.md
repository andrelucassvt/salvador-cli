# Redesenho Desktop do Salvador — Parte 4: Arquivos, preview e responsividade

> **Objetivo da parte:** completar o redesenho com árvore filtrável, preview seguro, rail direito, composer/estado vazio responsivos e documentação atualizada.
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** parte 3 concluída

## Contexto

O serviço de menções já indexa caminhos, mas não expõe hierarquia, tamanho nem preview. O novo painel deve permanecer confinado à raiz, não seguir diretórios por symlink e reutilizar a resolução segura das ferramentas ao ler o arquivo selecionado.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `lib/src/file_mentions.dart` | alterar | Expor a política compartilhada de diretórios ignorados sem mudar a expansão de menções |
| `lib/src/tools.dart` | alterar | Fazer a leitura confinada rejeitar binário e UTF-8 inválido com `ERRO:` |
| `test/salvador_cli_test.dart` | alterar | Contrato da leitura segura usada pelo preview |
| `app/lib/src/desktop/desktop_controller.dart` | alterar | Árvore, filtro, expansão, seleção e preview seguro |
| `app/lib/src/desktop/salvador_desktop_app.dart` | alterar | Painel direito, preview central, rails e acabamento responsivo |
| `app/test/desktop_controller_test.dart` | alterar | Indexação, filtro, symlinks, preview e menção |
| `app/test/salvador_desktop_app_test.dart` | alterar | Widget tests da árvore, preview, composer e viewports reduzidas |
| `docs/flow/app-desktop.md` | criar | Flow ponta a ponta do desktop redesenhado |
| `docs/flow/project-structure.md` | alterar | Novos módulos, estado persistente e responsabilidades atualizadas |

## Fases

### Fase 1 — Testes da árvore e do preview

> Os testes vão falhar inicialmente — isso é intencional.

- [ ] Ampliar `app/test/desktop_controller_test.dart` com uma raiz temporária contendo pastas, arquivos, ocultos, ignorados e symlink para fora.
- [ ] Testar raiz expandida por padrão, ordenação pasta-antes-de-arquivo, tamanhos, toggles de diretório e filtro por caminho/nome sem diferença de caixa.
- [ ] Testar que diretórios ignorados e symlinks não são percorridos e que preview fora da raiz retorna erro apresentável.
- [ ] Testar preview de UTF-8 com metadados/linhas e respostas claras para binário, arquivo grande, removido ou sem permissão.
- [ ] Adicionar em `test/salvador_cli_test.dart` casos de `read_file` com byte NUL e UTF-8 inválido, esperando `ERRO:` sem exceção propagada.
- [ ] Testar que “Mencionar com @” insere o caminho selecionado no composer usando a codificação existente para espaços.
- [ ] Verificação: `dart test test/salvador_cli_test.dart` e `cd app && flutter test test/desktop_controller_test.dart` compilam e falham somente pelos novos contratos.

### Fase 2 — Implementação da árvore e do preview

- [ ] Criar em `app/lib/src/desktop/desktop_controller.dart` o modelo imutável `WorkspaceTreeEntry` com caminho relativo, profundidade, tipo, expansão, tamanho e seleção.
- [ ] Tornar `FileMentionService.ignoredDirectories` público em `lib/src/file_mentions.dart` e indexar a raiz no controlador com `Directory.list(followLinks: false)`, sem atravessar links simbólicos.
- [ ] Alterar `ReadFileTool.execute` em `lib/src/tools.dart` para decodificar bytes explicitamente e devolver `ERRO:` via `ToolException` para binário/UTF-8 inválido, preservando o limite de 100.000 caracteres.
- [ ] Criar no `DesktopController` um `ToolRegistry` privado com `AgentPermissions.readOnly` e ler o preview por `execute(ToolCall(name: 'read_file', ...))`, reutilizando `WorkspaceTool.resolveFile` sem abrir `File(path)` direto.
- [ ] Expor no controlador `toggleDirectory`, `setFileFilter`, `openPreview`, `closePreview` e `mentionPreviewedFile`, atualizando a árvore após troca de raiz.
- [ ] Calcular linguagem/extensão, linhas, tamanho e conteúdo renderizável sem ultrapassar os limites já definidos para leitura/menção.
- [ ] Verificação: `dart test test/salvador_cli_test.dart` e `cd app && flutter test test/desktop_controller_test.dart` passam.

### Fase 3 — Painel direito e preview central

- [ ] Adicionar em `app/lib/src/desktop/salvador_desktop_app.dart` painel direito claro de 290 px com header, contador, filtro, árvore indentada e rodapé de escopo.
- [ ] Implementar pastas expandíveis e arquivos selecionáveis com estados visuais, tamanho, scroll e raiz aberta por padrão.
- [ ] Implementar rail direito de 50 px com expandir, arquivos e busca, preservando o estado do filtro ao recolher/reabrir.
- [ ] Alternar a área central entre chat/estado vazio e preview com header, metadados, “Mencionar com @”, fechar e corpo numerado selecionável.
- [ ] Aplicar destaque leve determinístico por spans para palavras-chave e tags conhecidas, mantendo fallback de texto puro para extensões desconhecidas.
- [ ] Verificação: `cd app && flutter analyze` passa e chaves dos estados árvore/preview/rail estão presentes para os widget tests.

### Fase 4 — Composer, estado vazio e widget tests

- [ ] Reestruturar `_Composer` em `app/lib/src/desktop/salvador_desktop_app.dart` com card de 12 px, textarea de 62 px e ações em `Wrap`, mantendo o botão enviar com largura fixa.
- [ ] Ajustar atalho para `⌘/Ctrl + Enter`, preservando quebra de linha normal e desabilitando envio durante loading/sending.
- [ ] Ajustar `_EmptyState` para região rolável com filhos não expansíveis, pasta ativa no subtítulo e ações “Entender o projeto”/“Revisar um arquivo”.
- [ ] Ampliar `app/test/salvador_desktop_app_test.dart` para árvore expandida/filtrada, seleção/fechamento do preview, menção, rails e erros de arquivo.
- [ ] Adicionar widget tests com largura e altura reduzidas que falhem em qualquer overflow do composer, estado vazio ou combinação dos dois rails.
- [ ] Verificação: `cd app && flutter test test/salvador_desktop_app_test.dart` passa sem app, janela ou device.

### Fase 5 — Verificação automatizada completa

- [ ] Rodar `dart format lib/src/file_mentions.dart lib/src/tools.dart test/salvador_cli_test.dart app/lib/src/desktop/desktop_controller.dart app/lib/src/desktop/salvador_desktop_app.dart app/test/desktop_controller_test.dart app/test/salvador_desktop_app_test.dart`.
- [ ] Rodar `dart analyze` e `dart test` na raiz.
- [ ] Rodar `cd app && flutter analyze && flutter test`.
- [ ] Rodar `git diff --check` e confirmar que nenhum arquivo em `app/macos/`, `app/linux/` ou `app/windows/` foi editado manualmente.
- [ ] Registrar para validação manual do usuário: fidelidade visual, picker, menus, carga/descarga real, modal, persistência após reinício, rails, filtro, preview e atalhos.
- [ ] Verificação: todos os quatro comandos de análise/teste terminam com exit code 0 e a lista manual fica no handoff final.

### Fase 6 — Atualizar flows e checkpoint final

- [ ] Invocar a skill `flow` para criar `docs/flow/app-desktop.md`, cobrindo bootstrap → restauração → descoberta do Ollama → top bar/configurações → sessão do agente → atividade → árvore/preview → persistência.
- [ ] Atualizar `docs/flow/project-structure.md` com `desktop_state_store.dart`, `system_memory.dart`, novos endpoints do Ollama e responsabilidades finais do desktop.
- [ ] Marcar nos metadados dos flows a revisão contra o commit/estado resultante e relacionar este plano.
- [ ] Verificar por `rg -n "DesktopStateStore|SystemMemoryReader|api/ps|preview|sessões" docs/flow` que os novos caminhos e regras aparecem na documentação.
- [ ] Checkpoint: commit das mudanças da parte + resumo final do redesenho concluído.

## Critérios de Sucesso

- [ ] Árvore filtrável permanece dentro da raiz e preview trata arquivos inválidos sem crash.
- [ ] Preview abre/fecha e insere a menção correta no composer.
- [ ] Os dois painéis alternam entre largura completa e rail sem overflow.
- [ ] Composer e estado vazio permanecem utilizáveis em janelas estreitas e baixas.
- [ ] `docs/flow/app-desktop.md` documenta o fluxo implementado e `project-structure.md` está atual.
- [ ] `dart analyze`, `dart test`, `flutter analyze`, `flutter test` e `git diff --check` passam.
- [ ] _(manual — feito pelo usuário)_ Redesign validado no app real conforme a referência visual.

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Árvore grande bloquear a thread de UI | Média | Indexação assíncrona, diretórios ignorados, expansão sob demanda e rebuilds com listas imutáveis |
| Highlight de código crescer para um editor completo | Média | Spans leves por padrões conhecidos, sem parser/dependência nem edição de arquivo |
| Symlink ou path relativo escapar da raiz | Alta | Não seguir links na árvore e validar novamente o caminho no mesmo confinamento usado pelas ferramentas antes da leitura |

## Rollback

Reverter o commit desta parte restaura a área central da parte 3. As APIs, preferências e histórico persistente continuam funcionais; nenhum arquivo do workspace é alterado pelo painel de preview.
