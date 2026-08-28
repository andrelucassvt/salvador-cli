# Migração do App Desktop para Clean Architecture — Parte 4: ChatCubit + FileExplorerCubit

> **Objetivo da parte:** `ChatCubit` (mensagens/atividades/envio) e `FileExplorerCubit` (árvore/filtro/preview/menções) funcionais e testados, registrados no `AppInjector`. Ainda sem UI consumindo.
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** Parte 3 concluída (`WorkspaceCubit` define o contrato de "sessão pronta"/"raiz atual" que estes dois Cubits recebem via `attachSession`/`setRoot`, acionados pela View na Parte 5/6)

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `app/lib/presentation/desktop/view_model/chat_state.dart` | criar | estados de mensagens/atividades/envio |
| `app/lib/presentation/desktop/view_model/chat_cubit.dart` | criar | substitui a parte de chat de `DesktopController` |
| `app/lib/presentation/desktop/view_model/file_explorer_state.dart` | criar | estados de árvore/filtro/preview |
| `app/lib/presentation/desktop/view_model/file_explorer_cubit.dart` | criar | substitui a parte de árvore/preview/menções de `DesktopController` |
| `app/lib/config/inject/app_injector.dart` | editar | registra `ChatRepository`/`WorkspaceRepository`/`ChatCubit`/`FileExplorerCubit` |
| `app/test/presentation/desktop/chat_cubit_test.dart` | criar | `blocTest` com fake de `ChatRepository` |
| `app/test/presentation/desktop/file_explorer_cubit_test.dart` | criar | `blocTest` com fake de `WorkspaceRepository` |

**Nota de execução (drift registrado):** `currentSessionSummary` acabou no `ChatState` (não no `WorkspaceState`, como o rascunho da Parte 3 sugeria) — é o `ChatCubit` quem conhece `sessionFirstPrompt`/`sessionStartedAt`/`activities.length`. `ChatCubit.newSession()` recebe `{required void Function(PersistedSessionSummaryEntity) onSessionEnded}` como parâmetro do próprio método (não algo fixado em `attachSession`); a View passa `(summary) => context.read<WorkspaceCubit>().recordSession(summary)`. `ChatState`/`FileExplorerState` seguem o mesmo padrão já registrado na Parte 3 (um único estado de conteúdo, sem `ChatError`/`Initial` separados) — `ChatErrorKind` ficou só com `{ sessionNotReady, sendFailed }` (sem `modelNotRunning`: a View computa um único `ready: bool` a partir do `WorkspaceState` antes de chamar `send`, então não há como o Cubit distinguir as duas causas).

## Fases

### Fase 1 — Testes do ChatCubit (contrato antes da implementação)

> Os testes vão falhar inicialmente — isso é intencional.

- [x] Passo 1: Criar `app/test/presentation/desktop/fakes/fake_chat_repository.dart` (`implements ChatRepository`, com `AppException? failure`, `StreamController<ToolActivityEntity>` exposto para o teste emitir atividades)
- [x] Passo 2: `attachSession(...)` limpa mensagens/atividades atuais e assina o novo `toolActivity` stream (porta `clearSession()` + `_rebuildSession()` de `desktop_controller.dart:498-505` e `640-656`)
- [x] Passo 3: `send(text)` recusa com `ChatErrorKind.sessionNotReady` quando `updateReadiness(false)` (porta a checagem de `desktop_controller.dart:544-554`); com sessão pronta, emite `sending: true`, chama o repository, adiciona a mensagem do usuário e a resposta na ordem certa
- [x] Passo 4: `newSession()` grava o resumo da sessão atual (título = primeiro prompt truncado em 80 caracteres, `desktop_controller.dart:479-496`) antes de limpar
- [x] Verificação: `cd app && flutter test test/presentation/desktop/chat_cubit_test.dart` falha por classes ainda não implementadas (erro de compilação nomeado) — confirmado

### Fase 2 — ChatState e ChatCubit

- [x] Passo 1: `sealed class ChatState` com `@immutable` + `toString()` abstrato: `ChatIdle` (messages, activities, sending, sessionFirstPrompt, sessionStartedAt, errorKind, error) + getter `currentSessionSummary`, mais `enum ChatErrorKind { sessionNotReady, sendFailed }`. Diferente do template padrão Initial/Loading/Loaded/Error: aqui "loading" é o campo `sending` dentro do estado de conteúdo, não um estado à parte — a lista de mensagens precisa continuar visível enquanto uma nova resposta carrega (mesmo comportamento de `isSending` em `desktop_controller.dart:148`, que nunca esconde `messages`)
- [x] Passo 2: Construtor de `ChatCubit` recebe `ChatRepository`; implementar `updateReadiness`, `attachSession`, `send`, `newSession`, `clearSession`, ouvindo `toolActivity` num `StreamSubscription` fechado em `close()`
- [x] Passo 3: Rodar os testes da Fase 1 contra o Cubit real
- [x] Verificação: `cd app && flutter test test/presentation/desktop/chat_cubit_test.dart` passa

### Fase 3 — Testes do FileExplorerCubit (contrato antes da implementação)

> Os testes vão falhar inicialmente — isso é intencional.

- [x] Passo 1: Criar `app/test/presentation/desktop/fakes/fake_workspace_repository.dart` (`implements WorkspaceRepository`)
- [x] Passo 2: `setRoot(root)` recarrega a árvore (porta `_resetWorkspaceContext`/`refreshTree`, `desktop_controller.dart:680-695`)
- [x] Passo 3: `toggleDirectory(path)` alterna `expanded` só da entrada afetada, preservando a ordem (porta `desktop_controller.dart:745-756`); `setFileFilter(query)` filtra achatando a árvore (porta `_applyVisibility`, `desktop_controller.dart:818-853`) — testar caso com filtro vazio (árvore hierárquica) e com filtro preenchido (lista achatada)
- [x] Passo 4: `openPreview(path)` com resultado de erro do repository emite `previewError` sem preview; com sucesso emite `FilePreviewEntity` (porta `desktop_controller.dart:767-790`)
- [x] Passo 5: `fileSuggestions`/`insertMention`/`mentionPreviewedFile` delegam ao repository/preview atual sem I/O (porta `desktop_controller.dart:524-535` e `800-816`)
- [x] Verificação: `cd app && flutter test test/presentation/desktop/file_explorer_cubit_test.dart` falha por classes ainda não implementadas (erro de compilação nomeado) — confirmado

### Fase 4 — FileExplorerState e FileExplorerCubit

- [x] Passo 1: `sealed class FileExplorerState` com `@immutable` + `toString()` abstrato: `FileExplorerLoaded` (treeEntries, fileFilter, preview, previewError) — árvore vazia inicial é só `treeEntries: const []`, sem estado `Initial` separado, pois `setRoot` é sempre chamado antes de qualquer render (porta o mesmo padrão de `treeEntries`/`fileFilter` getters de `desktop_controller.dart:163-164`)
- [x] Passo 2: Construtor de `FileExplorerCubit` recebe `WorkspaceRepository`; implementar `setRoot`, `toggleDirectory`, `setFileFilter`, `openPreview`, `closePreview`, `fileSuggestions`, `insertMention`, `mentionPreviewedFile`
- [x] Passo 3: Rodar os testes da Fase 3 contra o Cubit real
- [x] Verificação: `cd app && flutter test test/presentation/desktop/file_explorer_cubit_test.dart` passa

### Fase 5 — Registro no AppInjector e Checkpoint

- [x] Passo 1: Em `app_injector.dart`: `registerLazySingleton<ChatAgentDataSource>`, `registerLazySingleton<ChatRepository>(() => ChatRepositoryImpl(inject()))`, `registerLazySingleton<WorkspaceDataSource>`, `registerLazySingleton<WorkspaceRepository>(() => WorkspaceRepositoryImpl(inject()))`, `registerFactory<ChatCubit>(() => ChatCubit(inject()))`, `registerFactory<FileExplorerCubit>(() => FileExplorerCubit(inject()))`
- [x] Passo 2: `cd app && flutter analyze` sem erros em todo `lib/`
- [x] Checkpoint: commit das mudanças da parte ("presentation: ChatCubit e FileExplorerCubit") + resumo curto do que ficou pronto, seguindo direto para a Parte 5

## Critérios de Sucesso

- [x] `ChatCubit` cobre 100% do comportamento de mensagens/atividades/envio/sessões do `DesktopController` atual
- [x] `FileExplorerCubit` cobre 100% do comportamento de árvore/filtro/preview/menções do `DesktopController` atual
- [x] Ambos os States são `sealed class` com `toString()` legível
- [x] Ambos os Cubits registrados como `registerFactory`
- [x] Build sem erros
- [x] Todos os testes unitários da parte passando

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| `ChatCubit` e `FileExplorerCubit` não terem acesso direto a `WorkspaceCubit` (por design, ver índice) pode levar a esquecer de resetar um dos dois ao trocar pasta/modelo, reintroduzindo estado obsoleto | Média | A Fase 1/3 testam `attachSession`/`setRoot` como métodos públicos explícitos — a Parte 5/6 documenta exatamente onde a View os aciona via `MultiBlocListener`; nenhuma parte assume que os Cubits se sincronizam sozinhos |

## Rollback

`git revert` do commit desta parte. Nenhum dos dois Cubits é consumido por View ainda — reverter não afeta o app em execução.
