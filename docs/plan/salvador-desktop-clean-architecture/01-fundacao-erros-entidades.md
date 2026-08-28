# Migração do App Desktop para Clean Architecture — Parte 1: Fundação (erros, entidades, dependências)

> **Objetivo da parte:** `Result<T>`, a hierarquia `AppException`, as entidades de domínio e as dependências de state management/DI/teste instaladas e testadas, sem tocar ainda em `DesktopController` ou na UI.
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** nenhuma

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `app/pubspec.yaml` | editar | adiciona `flutter_bloc`, `get_it`; dev: `bloc_test`, `mocktail`, `checks` |
| `app/lib/config/error/result_pattern.dart` | criar | `Result<T>` (`Ok`/`Error`) com `.when()` |
| `app/lib/config/error/app_exception.dart` | criar | hierarquia `AppException` específica deste app (rede, Ollama, sistema de arquivos, validação) |
| `app/lib/domain/entities/chat_message_entity.dart` | criar | substitui `ChatEntry`/`ChatRole` de `desktop_controller.dart` |
| `app/lib/domain/entities/tool_activity_entity.dart` | criar | substitui `ToolActivity` |
| `app/lib/domain/entities/host_test_result_entity.dart` | criar | substitui `HostTestResult` |
| `app/lib/domain/entities/workspace_tree_entry_entity.dart` | criar | substitui `WorkspaceTreeEntry` |
| `app/lib/domain/entities/file_preview_entity.dart` | criar | substitui `FilePreview` |
| `app/lib/domain/entities/persisted_session_summary_entity.dart` | criar | substitui `PersistedSessionSummary` (hoje em `desktop_state_store.dart`) |
| `app/lib/domain/entities/desktop_preferences_entity.dart` | criar | substitui `DesktopPersistedState` |
| `app/lib/config/inject/app_injector.dart` | criar | esqueleto vazio de `AppInjector.setupDependencies()`, populado nas partes seguintes |
| `app/test/config/error/result_pattern_test.dart` | criar | testes do `Result<T>` |
| `app/test/domain/entities/*_entity_test.dart` | criar | testes de igualdade/`copyWith` das entidades com lista (`ChatMessageEntity`, `DesktopPreferencesEntity`) |

## Fases

### Fase 1 — Testes do `Result<T>` e das Entities com lista (contrato antes da implementação)

> Os testes vão falhar inicialmente (arquivos ainda não existem) — isso é intencional.

- [x] Passo 1: Criar `app/test/config/error/result_pattern_test.dart` testando: `Result.ok(v).when(ok: ..., error: ...)` chama o branch `ok`; `Result.isOk`/`Result.isError`; `Result.error(e).when(...)` chama o branch `error` com a exceção original preservada
- [x] Passo 2: Criar `app/test/domain/entities/chat_message_entity_test.dart` testando `==`/`hashCode` de duas `ChatMessageEntity` com a mesma lista `mentionedFiles` (valores iguais, listas diferentes na memória) e `copyWith()` preservando campos não alterados
- [x] Passo 3: Criar `app/test/domain/entities/desktop_preferences_entity_test.dart` testando `==`/`hashCode` com `recentRoots`/`sessions` (listas) e `copyWith()`
- [x] Verificação: `cd app && flutter test test/config/error/result_pattern_test.dart test/domain/entities/` falha por classe/arquivo inexistente (erro de compilação nomeado, não de sintaxe do próprio teste) — confirmado

### Fase 2 — Result Pattern e AppException

- [x] Passo 1: Implementar `app/lib/config/error/result_pattern.dart` com `sealed class Result<T>`, `Ok<T>`, `Error<T>`, `bool get isOk`/`isError`, e `R when<R>({required R Function(T) ok, required R Function(AppException) error})`
- [x] Passo 2: Implementar `app/lib/config/error/app_exception.dart` com `sealed class AppException implements Exception { message, cause, stackTrace }` e subclasses específicas deste app (substituem o `switch` de `_errorText` em `desktop_controller.dart:670-678`): `NetworkException` (equivalente a `SocketException`), `OllamaServerException` (equivalente a `OllamaException`), `AgentFailureException` (equivalente a `AgentException`), `FileSystemFailureException` (equivalente a `FileSystemException`), `InvalidInputException` (equivalente a `FormatException`, ex. host inválido), `UnknownException`
- [x] Verificação: `cd app && flutter test test/config/error/result_pattern_test.dart` passa

### Fase 3 — Entidades de domínio

- [x] Passo 1: `chat_message_entity.dart` — `enum ChatRole { user, assistant }` + `ChatMessageEntity({required role, required content, InferenceMetrics? metrics, mentionedFiles = const [], warnings = const []})`, campos de `package:salvador_cli` (`InferenceMetrics`) usados diretamente, sem duplicar
- [x] Passo 2: `tool_activity_entity.dart` — `ToolActivityEntity({required ToolCall call, required String result, required DateTime happenedAt})` com getter `summary` (portar a lógica de `ToolActivity.summary` em `desktop_controller.dart:46-52`)
- [x] Passo 3: `host_test_result_entity.dart`, `workspace_tree_entry_entity.dart` (com `copyWith({expanded, selected})`, portando `desktop_controller.dart:87-95`), `file_preview_entity.dart`, `persisted_session_summary_entity.dart`
- [x] Passo 4: `desktop_preferences_entity.dart` — `DesktopPreferencesEntity({Uri? host, String? model, InferenceOptions inference, AgentPermissions permissions, String? activeRoot, recentRoots = const [], sessions = const <PersistedSessionSummaryEntity>[]})`, com `copyWith()`, `==`/`hashCode` usando `listEquals`/`Object.hashAll` nas duas listas
- [x] Passo 5: Rodar os testes da Fase 1 contra as entidades reais
- [x] Verificação: `cd app && flutter test test/domain/entities/` passa

### Fase 4 — Dependências e esqueleto do AppInjector

- [x] Passo 1: `cd app && flutter pub add flutter_bloc get_it` e `flutter pub add --dev bloc_test mocktail checks`
- [x] Passo 2: Criar `app/lib/config/inject/app_injector.dart` com `class AppInjector { static GetIt inject = GetIt.instance; static Future<void> setupDependencies() async {} }` (corpo vazio — populado nas Partes 2–4)
- [x] Verificação: `cd app && flutter pub get && flutter analyze` sem erros

### Fase 5 — Checkpoint

- [x] Checkpoint: commit das mudanças da parte ("fundação: Result/AppException/entidades de domínio + dependências GetIt/Bloc") + resumo curto do que ficou pronto, seguindo direto para a Parte 2

## Critérios de Sucesso

- [ ] `Result<T>` e `AppException` implementados e testados
- [ ] Todas as entidades de domínio criadas com `@immutable`, `copyWith()`, `==`/`hashCode` corretos (incluindo `listEquals`/`hashAll` onde há lista)
- [ ] `flutter_bloc`, `get_it`, `bloc_test`, `mocktail`, `checks` instalados em `app/pubspec.yaml`
- [ ] Build sem erros
- [ ] Todos os testes unitários da parte passando

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Confundir a hierarquia `AppException` genérica do `data.md` (HTTP: `UnauthorizedException`/`ServerException` com `statusCode`) com o domínio real deste app (Ollama local + sistema de arquivos, sem HTTP autenticado) | Média | Usar os nomes específicos definidos na Fase 2 (`NetworkException`, `OllamaServerException`, `AgentFailureException`, `FileSystemFailureException`, `InvalidInputException`), mapeados 1:1 do `switch` existente em `desktop_controller.dart:670-678`, não a lista genérica do exemplo da skill |

## Rollback

`git revert` do commit desta parte. Nenhum arquivo existente é modificado além de `app/pubspec.yaml`/`pubspec.lock`; reverter não afeta `DesktopController` nem a UI, que continuam funcionando exatamente como antes.
