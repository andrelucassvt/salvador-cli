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

## Fases

### Fase 1 — Testes do WorkspaceCubit (contrato antes da implementação)

> Os testes vão falhar inicialmente — isso é intencional.

- [ ] Passo 1: Criar `app/test/presentation/desktop/fakes/fake_ollama_repository.dart` (`implements OllamaRepository`, com `AppException? failure` tipado, igual ao padrão `FakeProfileRepository` de `testing.md`) e `app/test/presentation/desktop/fakes/fake_desktop_storage_service.dart` (guarda em memória o último `DesktopPreferencesEntity` salvo)
- [ ] Passo 2: `app/test/presentation/desktop/workspace_cubit_test.dart` — `initialize()`: carrega preferências salvas, tenta conectar, emite `WorkspaceReady` com os modelos; sem modelo instalado emite `WorkspaceError(WorkspaceErrorKind.noModelsInstalled)` (porta a regra de `desktop_controller.dart:595-599`)
- [ ] Passo 3: Testar `selectRoot`: pasta inexistente emite erro sem persistir; pasta válida persiste `activeRoot` e atualiza `recentRoots` (dedupe, máx. 8 — porta `desktop_state_store.dart:157-165`)
- [ ] Passo 4: Testar `selectModel`/`startModel`/`stopModel`: cada um emite estado de "carregando" antes do resultado, e falha do repository não derruba o modelo já em execução (porta `desktop_controller.dart:328-331` e `365-369`)
- [ ] Passo 5: Testar `saveSettings`: valida host antes de sondar; se o host mudou e a sondagem não retorna nenhum modelo, falha sem persistir nada (porta `desktop_controller.dart:437-442`); se não mudou, persiste os novos parâmetros de inferência/permissões
- [ ] Verificação: `cd app && flutter test test/presentation/desktop/workspace_cubit_test.dart` falha por classes ainda não implementadas (erro de compilação nomeado)

### Fase 2 — WorkspaceState

- [ ] Passo 1: `sealed class WorkspaceState` com `@immutable` + `toString()` abstrato: `WorkspaceInitial`, `WorkspaceConnecting`, `WorkspaceReady` (host, root, models, runningModels, selectedModel, modelState, inference, permissions, recentRoots, sessions, currentSessionSummary, lastTestResult), `WorkspaceError(kind, {error, stackTrace})`
- [ ] Passo 2: `enum WorkspaceModelState { stopped, starting, running }` (substitui `ModelRunState`) e `enum WorkspaceErrorKind { invalidHost, folderNotFound, noModelsInstalled, connectionFailed, modelLoadFailed, saveSettingsFailed, generic }`
- [ ] Verificação: `cd app && flutter analyze lib/presentation/desktop/view_model/workspace_state.dart` sem erros

### Fase 3 — WorkspaceCubit (fazendo os testes da Fase 1 passarem)

- [ ] Passo 1: Construtor recebe `OllamaRepository`, `DesktopStorageService`; portar `initialize()` de `desktop_controller.dart:219-243`
- [ ] Passo 2: Portar `selectRoot`, `selectModel`, `startModel`, `stopModel`, `testHost`, `saveSettings`, `newSession`, `clearSession` (linhas 247-505 do arquivo original), sempre emitindo o estado de transição antes da chamada assíncrona e usando `result.when()`
- [ ] Passo 3: Cada método que persiste (root, modelo, configurações, sessões) chama `DesktopStorageService.save(...)` com o `DesktopPreferencesEntity` completo — igual à regra atual de "persistir só após sucesso" (`desktop_controller.dart:658-668`)
- [ ] Passo 4: Rodar os testes da Fase 1 contra o Cubit real
- [ ] Verificação: `cd app && flutter test test/presentation/desktop/workspace_cubit_test.dart` passa

### Fase 4 — Registro no AppInjector

- [ ] Passo 1: Em `app_injector.dart`, seguir a ordem services → datasources → repositories → cubits: `registerLazySingleton<DesktopStorageService>`, `registerLazySingleton<SystemMemoryService>`, `registerLazySingleton<OllamaRemoteDataSource>`, `registerLazySingleton<OllamaRepository>(() => OllamaRepositoryImpl(inject()))`, `registerFactory<WorkspaceCubit>(() => WorkspaceCubit(inject(), inject()))`
- [ ] Verificação: `cd app && flutter analyze lib/config/inject/` sem erros

### Fase 5 — Checkpoint

- [ ] Checkpoint: commit das mudanças da parte ("presentation: WorkspaceCubit com conexão/modelo/pasta/configurações") + resumo curto do que ficou pronto, seguindo direto para a Parte 4

## Critérios de Sucesso

- [ ] `WorkspaceCubit` cobre 100% do comportamento de conexão/modelo/pasta/configurações/sessões do `DesktopController` atual
- [ ] `WorkspaceState` é `sealed class` com `toString()` legível em todo estado
- [ ] `WorkspaceCubit` registrado como `registerFactory`; `OllamaRepository`/`DesktopStorageService` como `registerLazySingleton`
- [ ] Build sem erros
- [ ] Todos os testes unitários da parte passando

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| `saveSettings` hoje decide entre "host mudou" (sonda + substitui client) e "host igual" (só recria client com o modelo atual) — lógica fácil de simplificar incorretamente ao portar | Média | Fase 1 testa os dois ramos explicitamente antes da implementação (Passo 5); a implementação segue `desktop_controller.dart:419-465` linha a linha |

## Rollback

`git revert` do commit desta parte. `WorkspaceCubit` ainda não é consumido por nenhuma View — reverter não afeta o app em execução, que continua usando `DesktopController`.
