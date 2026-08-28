# Migração do App Desktop para Clean Architecture — Parte 3: WorkspaceCubit

> **Objetivo da parte:** `WorkspaceCubit` funcional e testado — conexão Ollama, seleção/ciclo de vida do modelo, pasta raiz, parâmetros de inferência, permissões e histórico de sessões — registrado no `AppInjector`. Ainda sem UI consumindo (a View só passa a usá-lo na Parte 5).
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** Parte 2 concluída (`OllamaRepository`, `DesktopStorageService`)

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `app/lib/presentation/desktop/view_model/workspace_state.dart` | criar | estados de conexão/modelo/pasta/configurações |
| `app/lib/presentation/desktop/view_model/workspace_cubit.dart` | criar | substitui a maior parte de `DesktopController` (exceto chat e árvore/preview) |
| `app/lib/config/inject/app_injector.dart` | editar | registra `OllamaRepository`/`DesktopStorageService`/`WorkspaceCubit` |
| `app/test/presentation/desktop/workspace_cubit_test.dart` | criar | `blocTest` com fake de `OllamaRepository` e de `DesktopStorageService` |

**Nota de execução (drift registrado):**
- `WorkspaceState` não separa `WorkspaceConnecting`/`WorkspaceError` como estados exclusivos do `WorkspaceReady`: existe só `WorkspaceInitial` (antes do primeiro `initialize()`) e `WorkspaceReady`, que carrega `connecting`/`modelState`/`errorKind`/`error` como campos do próprio conteúdo — mesmo padrão já adotado no `ChatState` da Parte 4 (justificado por `desktop_controller.dart` nunca esconder pasta/modelo/sessões durante reconexão ou falha; a seção "Feature com Paginação" de `view-model.md` endossa manter conteúdo visível durante transições).
- `currentSessionSummary` e `lastTestResult` **não** ficam no `WorkspaceState`: `currentSessionSummary` é responsabilidade do `ChatCubit` (Parte 4), que é quem conhece o primeiro prompt/data/contagem de atividades da sessão em andamento; `lastTestResult` e o método `testHost` ficam só no `SettingsCubit` (Parte 5), que é o único consumidor do botão "Testar". `WorkspaceCubit` ganhou em troca `recordSession(PersistedSessionSummaryEntity)`, chamado pela View quando `ChatCubit.newSession()` encerra uma sessão — é o `WorkspaceCubit` quem persiste, já que o resumo entra em `DesktopPreferencesEntity.sessions`.
- `newSession`/`clearSession` não existem no `WorkspaceCubit`: pertencem ao `ChatCubit` (mensagens/atividades são dele).

## Fases

### Fase 1 — Testes do WorkspaceCubit (contrato antes da implementação)

> Os testes vão falhar inicialmente — isso é intencional.

- [x] Passo 1: Criar `app/test/presentation/desktop/fakes/fake_ollama_repository.dart` (`implements OllamaRepository`, com `AppException? failure` tipado, igual ao padrão `FakeProfileRepository` de `testing.md`) e `app/test/presentation/desktop/fakes/fake_desktop_storage_service.dart` (guarda em memória o último `DesktopPreferencesEntity` salvo)
- [x] Passo 2: `app/test/presentation/desktop/workspace_cubit_test.dart` — `initialize()`: carrega preferências salvas, tenta conectar, emite `WorkspaceReady` com os modelos; sem modelo instalado emite `errorKind: WorkspaceErrorKind.noModelsInstalled` (porta a regra de `desktop_controller.dart:595-599`)
- [x] Passo 3: Testar `selectRoot`: pasta inexistente emite erro sem persistir; pasta válida persiste `activeRoot` e atualiza `recentRoots` (dedupe — porta `desktop_state_store.dart:157-165`)
- [x] Passo 4: Testar `startModel`/`stopModel`: cada um emite estado de "carregando" antes do resultado; falha ao **parar** o modelo não reporta "parado" às cegas — deriva de `runningModels` (porta `desktop_controller.dart:365-369`, achado durante a implementação e corrigido no teste antes de codar)
- [x] Passo 5: Testar `saveSettings`: valida host antes de sondar; se o host mudou e a sondagem não retorna nenhum modelo, falha sem persistir nada (porta `desktop_controller.dart:437-442`); se não mudou, persiste os novos parâmetros de inferência/permissões
- [x] Verificação: `cd app && flutter test test/presentation/desktop/workspace_cubit_test.dart` falha por classes ainda não implementadas (erro de compilação nomeado) — confirmado

### Fase 2 — WorkspaceState

- [x] Passo 1: `sealed class WorkspaceState` com `@immutable` + `toString()` abstrato: `WorkspaceInitial`, `WorkspaceReady` (host, root, connecting, modelState, models, runningModels, selectedModel, inference, permissions, recentRoots, sessions, errorKind, error) — ver nota de execução acima sobre a divergência do desenho original
- [x] Passo 2: `enum WorkspaceModelState { stopped, starting, running }` (substitui `ModelRunState`) e `enum WorkspaceErrorKind { invalidHost, folderNotFound, noModelsInstalled, connectionFailed, modelLoadFailed, saveSettingsFailed, generic }`
- [x] Verificação: `cd app && flutter analyze lib/presentation/desktop/view_model/workspace_state.dart` sem erros

### Fase 3 — WorkspaceCubit (fazendo os testes da Fase 1 passarem)

- [x] Passo 1: Construtor recebe `OllamaRepository`, `DesktopStorageService`; portar `initialize()` de `desktop_controller.dart:219-243`
- [x] Passo 2: Portar `selectRoot`, `selectModel`, `startModel`, `stopModel`, `saveSettings`, `recordSession` (substitui `newSession`/`clearSession`, que ficam no `ChatCubit`), sempre emitindo o estado de transição antes da chamada assíncrona e usando `switch` sobre `Result`/`result.when()`
- [x] Passo 3: Cada método que persiste (root, modelo, configurações, sessões) chama `DesktopStorageService.save(...)` com o `DesktopPreferencesEntity` completo — igual à regra atual de "persistir só após sucesso" (`desktop_controller.dart:658-668`)
- [x] Passo 4: Rodar os testes da Fase 1 contra o Cubit real
- [x] Verificação: `cd app && flutter test test/presentation/desktop/workspace_cubit_test.dart` passa

### Fase 4 — Registro no AppInjector

- [x] Passo 1: Em `app_injector.dart`, seguir a ordem services → datasources → repositories → cubits: `registerLazySingleton<DesktopStorageService>`, `registerLazySingleton<SystemMemoryReader>`, `registerLazySingleton<OllamaRemoteDataSource>`, `registerLazySingleton<OllamaRepository>(() => OllamaRepositoryImpl(inject()))`, `registerFactory<WorkspaceCubit>(() => WorkspaceCubit(inject(), inject(), memoryReader: inject()))`
- [x] Verificação: `cd app && flutter analyze lib/config/inject/` sem erros

### Fase 5 — Checkpoint

- [x] Checkpoint: commit das mudanças da parte ("presentation: WorkspaceCubit com conexão/modelo/pasta/configurações") + resumo curto do que ficou pronto, seguindo direto para a Parte 4

## Critérios de Sucesso

- [x] `WorkspaceCubit` cobre 100% do comportamento de conexão/modelo/pasta/configurações/sessões do `DesktopController` atual (chat e árvore/preview ficam para as Partes 4/5/6)
- [x] `WorkspaceState` é `sealed class` com `toString()` legível em todo estado
- [x] `WorkspaceCubit` registrado como `registerFactory`; `OllamaRepository`/`DesktopStorageService` como `registerLazySingleton`
- [x] Build sem erros
- [x] Todos os testes unitários da parte passando

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| `saveSettings` hoje decide entre "host mudou" (sonda + substitui client) e "host igual" (só recria client com o modelo atual) — lógica fácil de simplificar incorretamente ao portar | Média | Fase 1 testa os dois ramos explicitamente antes da implementação (Passo 5); a implementação segue `desktop_controller.dart:419-465` linha a linha |

## Rollback

`git revert` do commit desta parte. `WorkspaceCubit` ainda não é consumido por nenhuma View — reverter não afeta o app em execução, que continua usando `DesktopController`.
