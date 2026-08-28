# Migração do App Desktop para Clean Architecture — Parte 5: View — shell, top bar, configurações, atividade

> **Objetivo da parte:** `main.dart` inicializa o `AppInjector`; o shell resolve os 4 Cubits (`WorkspaceCubit`, `ChatCubit`, `FileExplorerCubit`, `SettingsCubit`) e sincroniza-os via `MultiBlocListener`; top bar, menus, diálogo de configurações e painel/rail de atividade passam a consumir os Cubits em vez do `DesktopController`. `DesktopController` continua existindo até a Parte 6 (removido só depois que a Parte 6 migrar o restante da tela).
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** Parte 4 concluída (`WorkspaceCubit`, `ChatCubit`, `FileExplorerCubit` prontos)

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `app/lib/presentation/desktop/view_model/settings_state.dart` | criar | estado do formulário de configurações |
| `app/lib/presentation/desktop/view_model/settings_cubit.dart` | criar | edição local + `testHost`/`saveSettings` (delega a `OllamaRepository` e ao `WorkspaceCubit.saveSettings` via callback exposto pela View) |
| `app/lib/main.dart` | editar | chama `AppInjector.setupDependencies()` antes de `runApp` |
| `app/lib/src/desktop/salvador_desktop_app.dart` | editar | `_ShellScreenState` resolve os 4 Cubits via `AppInjector.inject.get<...>()`; adiciona `MultiBlocListener` (WorkspaceCubit → `ChatCubit.attachSession`/`FileExplorerCubit.setRoot`) |
| `app/lib/presentation/desktop/widgets/mac_title_bar.dart` | criar (mover de `salvador_desktop_app.dart:371-409`) | `_MacTitleBar` sem mudança de comportamento |
| `app/lib/presentation/desktop/widgets/logo_mark.dart` | criar (mover de `:476-515`) | `_LogoMark` |
| `app/lib/presentation/desktop/widgets/folder_menu.dart` | criar (mover de `:517-667`) | `_FolderMenu`/`_FolderMenuItem`, lendo `root`/`recentRoots` do `WorkspaceState` |
| `app/lib/presentation/desktop/widgets/model_menu.dart` | criar (mover de `:669-910`) | `_ModelMenu`/`_ModelMenuItem`/`_StatusPill`, lendo `models`/`runningModels`/`selectedModel` do `WorkspaceState` |
| `app/lib/presentation/desktop/widgets/start_stop_button.dart` | criar (mover de `:912-1004`) | `_StartStopButton`, lendo `modelState` do `WorkspaceState` |
| `app/lib/presentation/desktop/content/workspace_top_bar.dart` | criar (mover de `:411-474`) | `_WorkspaceTopBar`, compõe os widgets acima |
| `app/lib/presentation/desktop/content/settings_dialog.dart` | criar (mover de `:1006-1425`) | `_SettingsDialog`, migrado de `StatefulWidget` próprio para `BlocBuilder<SettingsCubit, SettingsState>` |
| `app/lib/presentation/desktop/widgets/dialog_label.dart`, `slider_setting.dart` | criar (mover de `:1359-1425`) | sem mudança de comportamento |
| `app/lib/presentation/desktop/widgets/activity_panel.dart`, `activity_rail.dart`, `session_tile.dart`, `rail_icon.dart`, `no_activity.dart`, `activity_tile.dart` | criar (mover de `:2121-2416`, `:2866-3000`) | lendo `sessions`/`currentSessionSummary` do `WorkspaceState` e `activities` do `ChatState` |
| `app/test/presentation/desktop/settings_cubit_test.dart` | criar | `blocTest` do formulário |

## Fases

### Fase 1 — Testes do SettingsCubit (contrato antes da implementação)

> Os testes vão falhar inicialmente — isso é intencional.

- [ ] Passo 1: Criar `app/test/presentation/desktop/settings_cubit_test.dart` reutilizando `FakeOllamaRepository` da Parte 3: `updateField` (host/temperatura/contexto/keepAlive/timeout/permissões) atualiza só o campo editado no estado, preservando os demais (porta o padrão de `_SettingsDialogState` com múltiplos `setState`)
- [ ] Passo 2: Testar `testHost(text)`: host inválido emite `SettingsError(SettingsErrorKind.invalidHost)` sem chamar o repository; host válido emite o resultado do probe (`HostTestResultEntity`) sem alterar os demais campos do formulário (porta `desktop_controller.dart:372-408`)
- [ ] Passo 3: Testar `save()`: delega ao callback `onSave` (injetado via construtor, que a View liga a `WorkspaceCubit.saveSettings`) e emite `SettingsSaved` só se o callback resolver sem exceção; propaga a `AppException` do callback como `SettingsError` sem fechar o formulário
- [ ] Verificação: `cd app && flutter test test/presentation/desktop/settings_cubit_test.dart` falha por classes ainda não implementadas (erro de compilação nomeado)

### Fase 2 — SettingsState e SettingsCubit

- [ ] Passo 1: `sealed class SettingsState` com `@immutable` + `toString()` abstrato: `SettingsEditing` (hostText, temperature, contextText, keepAlive, timeout, allowEdit, allowCommands, testing: bool, testResult, saving: bool), `SettingsError(kind, {error})`, `SettingsSaved`; `enum SettingsErrorKind { invalidHost, saveFailed }`
- [ ] Passo 2: `SettingsCubit(this._ollamaRepository)` com estado inicial construído a partir dos valores atuais do `WorkspaceState` (a View passa esses valores no construtor via `SettingsCubit.fromWorkspace(WorkspaceReady state, OllamaRepository repo)`); implementar `updateField`, `testHost`, e `save({required Future<void> Function(...) onSave})`
- [ ] Passo 3: Rodar os testes da Fase 1 contra o Cubit real
- [ ] Verificação: `cd app && flutter test test/presentation/desktop/settings_cubit_test.dart` passa

### Fase 3 — Bootstrap do AppInjector e resolução dos Cubits no shell

- [ ] Passo 1: Em `app_injector.dart`, adicionar `registerFactory<SettingsCubit>` (recebe `OllamaRepository`)
- [ ] Passo 2: Em `main.dart`, chamar `await AppInjector.setupDependencies();` logo após `WidgetsFlutterBinding.ensureInitialized()`, antes de `runApp`
- [ ] Passo 3: Em `_ShellScreenState.initState` (`salvador_desktop_app.dart:137-149`), resolver `_workspaceCubit = AppInjector.inject.get<WorkspaceCubit>()`, `_chatCubit = ... get<ChatCubit>()`, `_fileExplorerCubit = ... get<FileExplorerCubit>()`, chamando `_workspaceCubit.initialize()` no primeiro frame (substitui `_controller.initialize()`); fechar os três em `dispose()` (`_cubit.close()`, conforme `di.md`)
- [ ] Passo 4: Envolver a árvore de widgets do shell num `MultiBlocProvider` com os 3 Cubits e um `MultiBlocListener` que, ao `WorkspaceState` mudar de `root`/passar a `WorkspaceReady` com nova sessão pronta, chama `context.read<FileExplorerCubit>().setRoot(state.root)` e `context.read<ChatCubit>().attachSession(...)` com os parâmetros atuais de host/modelo/permissões
- [ ] Verificação: `cd app && flutter analyze lib/main.dart lib/src/desktop/salvador_desktop_app.dart` sem erros

### Fase 4 — Top bar e diálogo de configurações

- [ ] Passo 1: Extrair `_MacTitleBar`, `_LogoMark`, `_FolderMenu`+`_FolderMenuItem`, `_ModelMenu`+`_ModelMenuItem`+`_StatusPill`, `_StartStopButton` para `presentation/desktop/widgets/`, preservando todas as `Key(...)` existentes; cada um passa a receber `WorkspaceState` (ou os campos específicos que já usa) em vez de `DesktopController`
- [ ] Passo 2: Extrair `_WorkspaceTopBar` para `presentation/desktop/content/workspace_top_bar.dart`, envolvida em `BlocBuilder<WorkspaceCubit, WorkspaceState>`
- [ ] Passo 3: Extrair `_SettingsDialog` para `presentation/desktop/content/settings_dialog.dart`: remove `_SettingsDialogState` e os `TextEditingController`/`setState` locais, substituindo por `BlocBuilder<SettingsCubit, SettingsState>` + `context.read<SettingsCubit>().updateField(...)` nos `onChanged`; ao abrir o diálogo (`_openSettings` em `salvador_desktop_app.dart:241-246`), criar o `SettingsCubit` via `AppInjector` com um `BlocProvider` escopado ao próprio `showDialog`
- [ ] Passo 4: Extrair `_DialogLabel`/`_SliderSetting` para `presentation/desktop/widgets/`
- [ ] Verificação: `cd app && flutter analyze` sem erros; `dart format --output=none --set-exit-if-changed app/lib/presentation/` sem diffs pendentes

### Fase 5 — Painel e rail de atividade/sessões

- [ ] Passo 1: Extrair `_ActivityPanel`/`_ActivityRail`/`_SessionTile`/`_RailIcon`/`_NoActivity`/`_ActivityTile` para `presentation/desktop/widgets/`, preservando as `Key(...)` existentes
- [ ] Passo 2: `_ActivityPanel`/`_ActivityRail` passam a ler `sessions`/`currentSessionSummary` de `BlocBuilder<WorkspaceCubit, WorkspaceState>` e `activities` de `BlocBuilder<ChatCubit, ChatState>` (dois builders combinados, já que hoje as duas informações vêm do mesmo `DesktopController`)
- [ ] Passo 3: Botão "Nova sessão" da top bar (`salvador_desktop_app.dart:444-460`) passa a chamar `context.read<ChatCubit>().newSession()`, que internamente pede ao `WorkspaceCubit` (via callback passado em `attachSession`, não referência direta a Cubit) para persistir o resumo — ver Fase 1/Passo 4 da Parte 4
- [ ] Verificação: `cd app && flutter analyze` sem erros

### Fase 6 — Checkpoint

- [ ] Checkpoint: commit das mudanças da parte ("view: shell, top bar, configurações e atividade migrados para os Cubits") + resumo curto do que ficou pronto, seguindo direto para a Parte 6

## Critérios de Sucesso

- [ ] `main.dart` inicializa o `AppInjector` antes de `runApp`
- [ ] Top bar, menus, diálogo de configurações e painel/rail de atividade não referenciam mais `DesktopController`
- [ ] Todas as `Key(...)` existentes preservadas nos widgets movidos
- [ ] Build sem erros
- [ ] Todos os testes unitários da parte passando
- [ ] _(manual — feito pelo usuário)_ Validação funcional no app: abrir a pasta, trocar modelo, abrir configurações, ver painel de atividade/sessões

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| `DesktopController` e os novos Cubits coexistirem nesta parte (a tela ainda usa o controlador antigo para árvore/preview/chat até a Parte 6) pode gerar dois "donos" de estado divergentes se algo vazar entre os dois | Média | Nesta parte o `DesktopController` continua a única fonte para árvore/preview/chat — os widgets migrados leem exclusivamente os novos Cubits; nenhuma leitura mista dentro do mesmo widget |
| Extrair `_SettingsDialog` para `Cubit` pode quebrar o fluxo de "Testar" → "Salvar e reconectar" se o `SettingsCubit` não representar corretamente os estados intermediários (`testing`, `saving`) que hoje são `bool` locais | Média | Fase 1 testa `testing`/`saving` como parte do `SettingsEditing` antes de qualquer UI; a Fase 4 só liga botões a esses campos, sem lógica nova |

## Rollback

`git revert` do commit desta parte. `DesktopController` continua presente e funcional (removido só na Parte 6); reverter restaura a top bar/configurações/atividade antigas sem afetar o restante do app.
