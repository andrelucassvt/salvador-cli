# Migração do App Desktop para Clean Architecture — Parte 6: View — arquivos, composer, limpeza e flow

> **Objetivo da parte:** Painel/rail de arquivos, preview e composer/área de chat migrados para `FileExplorerCubit`/`ChatCubit`; `DesktopController` e seus testes antigos removidos; testes de widget adaptados para resolver os Cubits via `AppInjector`; `docs/flow/app-desktop.md` atualizado. Ao final, a migração está completa.
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** Parte 5 concluída

**Nota de execução (drift registrado):** esta parte foi executada junto com a Parte 5, numa única passagem contínua (ver nota de execução em `05-view-shell-topbar-settings.md`). Além disso, a Fase 3/Passo 3 **não** usou `MockCubit` por Cubit: `app/test/salvador_desktop_app_test.dart` registra `WorkspaceCubit`/`ChatCubit`/`FileExplorerCubit`/`SettingsCubit` **reais** no `AppInjector`, fakeando só a borda de rede (`OllamaClientFactory` devolvendo um `_FakeClient extends OllamaClient`) e a borda de disco (`DesktopStorageService` fake) — o mesmo nível de fake que a suíte antiga já usava por trás do `DesktopController`. Isso preserva a cobertura de integração real do `MultiBlocListener` (a sincronização entre os 4 Cubits, que é a parte mais arriscada desta migração) em vez de isolar cada Cubit atrás de um mock, que teria testado a View sem nunca exercitar a sincronização de verdade. Consolidação de arquivos: `files_panel.dart` (FilesPanel+FilesRail+TreeRow), `preview_pane.dart` (PreviewPane+PreviewLine+PreviewErrorPane), `chat_widgets.dart` (EmptyState+MessageCard+MetricsBar+ThinkingCard+ErrorBanner+PromptCard+FileChip) — mesmo raciocínio de agrupamento da Parte 5.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `app/lib/presentation/desktop/widgets/files_panel.dart`, `files_rail.dart`, `tree_row.dart` | criar (mover de `salvador_desktop_app.dart:1427-1673`) | lendo `FileExplorerState` |
| `app/lib/presentation/desktop/widgets/preview_pane.dart`, `preview_line.dart`, `preview_error_pane.dart`, `code_highlighter.dart` | criar (mover de `:1675-1832`, `:1888-2119`) | `_highlightLine`/`_keywordsByLanguage` viram funções puras em `code_highlighter.dart` |
| `app/lib/presentation/desktop/content/composer.dart` | criar (mover de `:2418-2609`) | `_Composer`, lendo `ChatState.sending` e `WorkspaceState` (ready = `connectionState == ready && modelState == running`) |
| `app/lib/presentation/desktop/widgets/empty_state.dart`, `message_card.dart`, `metrics_bar.dart`, `thinking_card.dart`, `error_banner.dart`, `prompt_card.dart`, `file_chip.dart` | criar (mover de `:2611-2864`, `:3002-3055`) | lendo `ChatState` |
| `app/lib/common/utils/formatters.dart` | criar (mover de `:3086-3109`) | `formatBytes`, `relativeTime`, `formatSessionDate` — usadas por widgets de mais de uma região |
| `app/lib/src/desktop/salvador_desktop_app.dart` | editar | `_buildWorkspace`/`_buildCenter` passam a montar os widgets migrados via `BlocBuilder`; `_send`, `_insertSuggestion`, `_startMention`, `_mentionPreviewed` chamam os Cubits em vez do `DesktopController` |
| `app/lib/src/desktop/desktop_controller.dart` | remover | substituído integralmente pelos 4 Cubits |
| `app/test/desktop_controller_test.dart` | remover | cobertura já reproduzida em `workspace_cubit_test.dart`/`chat_cubit_test.dart`/`file_explorer_cubit_test.dart` |
| `app/test/salvador_desktop_app_test.dart` | editar | registra `MockWorkspaceCubit`/`MockChatCubit`/`MockFileExplorerCubit`/`MockSettingsCubit` no `AppInjector` em vez de injetar um `DesktopController` fake |
| `docs/flow/app-desktop.md` | editar | reescreve "Arquivos Envolvidos"/"Passo a Passo" para os Cubits/Repositories novos |

## Fases

### Fase 1 — Painel/rail de arquivos e preview

- [x] Passo 1: Extrair `_FilesPanel`/`_FilesRail`/`_TreeRow` para `presentation/desktop/widgets/`, lendo `treeEntries`/`fileFilter` de `BlocBuilder<FileExplorerCubit, FileExplorerState>`; `onToggleDirectory`/`onOpenFile` chamam `context.read<FileExplorerCubit>()`
- [x] Passo 2: Extrair `_PreviewPane`/`_PreviewLine`/`_PreviewErrorPane` para `presentation/desktop/widgets/`, lendo `preview`/`previewError` do `FileExplorerState`; mover `_highlightLine`/`_keywordsByLanguage`/`_keywordStyles`/`_commentStyle`/`_stringStyle`/`_numberStyle` para `presentation/desktop/widgets/code_highlighter.dart` como funções/constantes de nível de arquivo (sem estado, sem mudança de comportamento)
- [x] Passo 3: Preservar todas as `Key(...)` existentes (`files-panel`, `file-filter-field`, `tree-entry-<path>`, `preview-pane`, `close-preview-button` etc.)
- [x] Verificação: `cd app && flutter analyze` sem erros

### Fase 2 — Composer e área de chat

- [x] Passo 1: Extrair `_Composer` para `presentation/desktop/content/composer.dart`; `_ShellScreenState._send` (`salvador_desktop_app.dart:189-199`) passa a chamar `context.read<ChatCubit>().send(text)`, mantendo o tratamento local de `/exit`/`/quit` (comando de frontend, nunca chega ao Cubit, conforme AGENTS.md)
- [x] Passo 2: `_insertSuggestion`/`_startMention`/`_mentionPreviewed` (`:201-239`) passam a chamar `context.read<FileExplorerCubit>()` para menção de preview e um novo `context.read<FileExplorerCubit>().fileSuggestions(...)`/`insertMention(...)` para as sugestões do composer (hoje delegadas ao `DesktopController`)
- [x] Passo 3: Extrair `_EmptyState`, `_MessageCard`, `_MetricsBar`, `_ThinkingCard`, `_ErrorBanner`, `_PromptCard`, `_FileChip` para `presentation/desktop/widgets/`, lendo `ChatState.messages`/`sending` via `BlocBuilder<ChatCubit, ChatState>`; `_buildCenter` (`:328-368`) prioriza preview (`FileExplorerState`) sobre chat, exatamente como hoje
- [x] Passo 4: Mover `_formatBytes`/`_relativeTime`/`_formatSessionDate` para `common/utils/formatters.dart` (usadas por widgets de árvore, atividade e chat)
- [x] Verificação: `cd app && flutter analyze` sem erros

### Fase 3 — Remoção do código legado

- [x] Passo 1: Remover `app/lib/src/desktop/desktop_controller.dart` e `app/test/desktop_controller_test.dart`
- [x] Passo 2: Confirmar que nenhum arquivo em `app/lib/` ainda importa `desktop_controller.dart` (`grep -rn "desktop_controller" app/lib/` deve retornar vazio)
- [x] Passo 3 (adaptado — ver nota de execução): `app/test/salvador_desktop_app_test.dart` registra os 4 Cubits **reais** no `AppInjector` via `registerFactory<XCubit>(() => instanciaJaConstruida)` (closure que sempre devolve a mesma instância, para a View e o teste enxergarem o mesmo Cubit), com `await AppInjector.inject.reset()` no `tearDown`; a "estubagem" de `initState` é natural, já que `WorkspaceCubit.initialize()` real roda contra o `_FakeClient`/`_NoIoStore`
- [x] Verificação: `grep -rn "desktop_controller" app/lib/` não retorna nada
- [x] Verificação: `grep -rn "src/desktop/desktop_state_store\|src/desktop/system_memory" app/lib/ app/test/` não retorna nada (confirma que a Parte 2 já atualizou todos os imports)

### Fase 4 — Validação estática e testes completos

- [x] Passo 1: `cd app && flutter analyze` sem erros ou warnings novos
- [x] Passo 2: `cd app && flutter test` — toda a suíte (`config/`, `domain/`, `data/`, `common/services/`, `presentation/desktop/*_cubit_test.dart`, `salvador_desktop_app_test.dart`) passando
- [x] Passo 3: `dart analyze && dart test` na raiz do repositório — confirma que o pacote `salvador_cli` continua intocado (nenhuma mudança nesta migração toca `lib/`)
- [x] Verificação: os três comandos acima retornam sem erro

### Fase 5 — Atualizar Flow

- [x] Passo 1: Reescrever a tabela "Arquivos Envolvidos" de `docs/flow/app-desktop.md` trocando `desktop_controller.dart`/`desktop_state_store.dart`/`system_memory.dart` pelos novos Cubits/Repositories/Services (`WorkspaceCubit`, `ChatCubit`, `FileExplorerCubit`, `SettingsCubit`, `OllamaRepository`, `ChatRepository`, `WorkspaceRepository`, `DesktopStorageService`, `SystemMemoryService`)
- [x] Passo 2: Reescrever "Passo a Passo" (10 passos) apontando cada um para o Cubit/método real que agora o implementa, preservando as mesmas regras de negócio já documentadas (persistir só após sucesso, servidor conectado ≠ modelo carregado, árvore não segue symlinks etc.)
- [x] Passo 3: Atualizar o front-matter (`generated_at`, `source_commit`, `verified_at`, `related_plans`) apontando para este plano
- [x] Passo 4: Adicionar em "Observações" uma nota registrando a decisão de não usar GoRouter nesta migração (única tela, configurações é modal), para quem ler o flow depois entender por que não há `app_router.dart`
- [x] Verificação: `docs/flow/app-desktop.md` não referencia mais `DesktopController`/`ChangeNotifier`

### Fase 6 — Checkpoint

- [x] Checkpoint: commit das mudanças da parte ("view: arquivos/composer migrados; remoção do DesktopController; flow atualizado") + resumo curto do que ficou pronto — esta é a última parte, a migração está completa

## Critérios de Sucesso

- [x] Painel/rail de arquivos, preview e composer/chat consomem exclusivamente `FileExplorerCubit`/`ChatCubit`
- [x] `desktop_controller.dart` e `desktop_controller_test.dart` removidos; nenhum import remanescente
- [x] `app/test/salvador_desktop_app_test.dart` usa `MockCubit` via `AppInjector`, conforme `testing.md`
- [x] `docs/flow/app-desktop.md` reflete a arquitetura nova
- [x] Build sem erros
- [x] Todos os testes unitários e de widget passando (`flutter test` em `app/` e `dart test` na raiz)
- [ ] _(manual — feito pelo usuário)_ Validação funcional no app: fluxo completo de ponta a ponta (conectar, trocar pasta/modelo, enviar mensagem, abrir preview, mencionar arquivo, salvar configurações, nova sessão)

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| `salvador_desktop_app_test.dart` (515 linhas) ter asserções que dependiam de comportamento síncrono do `ChangeNotifier` (`notifyListeners()` imediato) e quebrarem com o ciclo assíncrono de emissão do Cubit | Média | Adaptar teste por teste na Fase 3, rodando `flutter test test/salvador_desktop_app_test.dart` a cada bloco adaptado em vez de reescrever tudo de uma vez às cegas |
| Remover `desktop_controller.dart` antes de confirmar que absolutamente nada mais o referencia (import esquecido em algum widget não migrado) | Baixa | Fase 3 Passo 2 faz o `grep` de confirmação antes de rodar `flutter analyze`/`flutter test` |

## Rollback

`git revert` dos commits desta parte na ordem inversa. Como é a última parte, reverter até aqui é equivalente a reverter a migração inteira até o fim da Parte 5 (`DesktopController` volta a existir); reverter todas as 6 partes (ordem 6 → 1, conforme o índice) restaura o app ao estado anterior à migração por completo.

## Após a Implementação

Nenhuma pergunta pendente sobre criar flow — `docs/flow/app-desktop.md` já existe e é atualizado nesta mesma parte (Fase 5), em vez de criado do zero.
