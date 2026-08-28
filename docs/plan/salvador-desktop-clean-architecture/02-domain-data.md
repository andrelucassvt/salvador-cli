# Migração do App Desktop para Clean Architecture — Parte 2: Domain (interfaces) + Data (DataSources/RepositoryImpl)

> **Objetivo da parte:** Interfaces de Repository e implementações (Ollama, Chat/Agente, Workspace) mais `DesktopStorageService`, todos testados com fakes, sem nenhum Cubit ainda consumindo-os.
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** Parte 1 concluída (`Result<T>`, `AppException`, entidades)

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `app/lib/domain/interfaces/ollama_repository.dart` | criar | contrato: testar conexão, listar modelos/instalados/em execução, carregar/descarregar modelo, consultar contexto do modelo |
| `app/lib/domain/interfaces/chat_repository.dart` | criar | contrato: configurar sessão do agente, enviar mensagem, observar atividades de ferramenta, limpar sessão |
| `app/lib/domain/interfaces/workspace_repository.dart` | criar | contrato: listar árvore de arquivos, ler preview de arquivo, sugerir/inserir menções `@arquivo` |
| `app/lib/data/datasources/ollama_remote_datasource.dart` | criar | encapsula a criação de `OllamaClient` (pacote `salvador_cli`) e chama seus métodos HTTP |
| `app/lib/data/datasources/chat_agent_datasource.dart` | criar | encapsula `AgentSession` (pacote `salvador_cli`), que é stateful |
| `app/lib/data/datasources/workspace_datasource.dart` | criar | encapsula `ToolRegistry` (leitura, `AgentPermissions.readOnly`) e `FileMentionService`, mais a indexação de árvore (`Directory.listSync`) |
| `app/lib/data/repositories/ollama_repository_impl.dart` | criar | implementa `OllamaRepository`, classifica falhas em `AppException` |
| `app/lib/data/repositories/chat_repository_impl.dart` | criar | implementa `ChatRepository` |
| `app/lib/data/repositories/workspace_repository_impl.dart` | criar | implementa `WorkspaceRepository` |
| `app/lib/common/services/desktop_storage_service.dart` | criar (move de `app/lib/src/desktop/desktop_state_store.dart`) | persistência local em JSON versionado — reaproveita a lógica de `DesktopStateStore`, tipada com `DesktopPreferencesEntity`/`PersistedSessionSummaryEntity` |
| `app/lib/common/services/system_memory_service.dart` | mover de `app/lib/src/desktop/system_memory.dart` | RAM disponível do sistema — implementação inalterada, só relocada para `common/services/` |
| `app/test/data/**/*_repository_impl_test.dart` | criar | testes com fakes de DataSource |
| `app/test/data/**/fakes/*.dart` | criar | fakes concretos dos DataSources |
| `app/test/common/services/desktop_storage_service_test.dart` | mover/adaptar de `app/test/desktop_state_store_test.dart` | mesmos cenários, tipos novos |
| `app/test/common/services/system_memory_service_test.dart` | mover de `app/test/system_memory_test.dart` | sem mudança de comportamento |

**Nota de design (registrada, não decidida silenciosamente):** `AgentSession` (pacote `salvador_cli`) é stateful — mantém histórico da conversa internamente e expõe um callback `onToolResult` síncrono, não um par requisição/resposta puro. `ChatRepository` foge por isso do molde "todo método é uma chamada stateless" do `data.md`: expõe `configureSession(...)` (recria a sessão), `Stream<ToolActivityEntity> get toolActivity` (adapta o callback `onToolResult` para stream, para o `ChatCubit` da Parte 4 escutar em vez de receber uma closure) e `send`/`clearSession`. Ainda assim retorna `Result<T>` e classifica erros em `AppException`, preservando o restante do contrato.

## Fases

### Fase 1 — Testes dos RepositoryImpl com fakes de DataSource (contrato antes da implementação)

> Os testes vão falhar inicialmente — isso é intencional.

- [ ] Passo 1: Criar `app/test/data/ollama/fakes/fake_ollama_remote_datasource.dart` (`implements OllamaRemoteDataSource`, com campos `shouldThrow`/exceção customizável) e `app/test/data/ollama/ollama_repository_impl_test.dart` cobrindo: `testConnection` sucesso e `SocketException` → `NetworkException`; `listModels` sucesso e lista vazia (hoje vira `OllamaException` em `desktop_controller.dart:596-599`) → `OllamaServerException`
- [ ] Passo 2: Criar `app/test/data/chat/fakes/fake_chat_agent_datasource.dart` e `app/test/data/chat/chat_repository_impl_test.dart` cobrindo: `send` sucesso retornando `AgentTurnResult`; `send` com `AgentException` → `AgentFailureException`; `toolActivity` emite um evento após uma chamada de ferramenta simulada no fake
- [ ] Passo 3: Criar `app/test/data/workspace/fakes/fake_workspace_datasource.dart` e `app/test/data/workspace/workspace_repository_impl_test.dart` cobrindo: `listTree` sucesso; `readFile` com resultado `ERRO:` do `ToolRegistry` (comportamento de `desktop_controller.dart:767-790`) → `Result.error` com `FileSystemFailureException`
- [ ] Verificação: `cd app && flutter test test/data/` falha por classes/arquivos ainda não implementados (erro de compilação nomeado)

### Fase 2 — Interfaces de domínio

- [ ] Passo 1: `ollama_repository.dart` — `abstract class OllamaRepository { Future<Result<void>> testConnection({required Uri host}); Future<Result<List<OllamaModelInfo>>> listModels({required Uri host}); Future<Result<List<OllamaRunningModel>>> listRunningModels({required Uri host, required List<OllamaModelInfo> installed}); Future<Result<void>> loadModel({required Uri host, required String model, required Duration keepAlive}); Future<Result<void>> unloadModel({required Uri host, required String model}); Future<Result<int?>> showModelContext({required Uri host, required String model}); }`
- [ ] Passo 2: `chat_repository.dart` — `abstract class ChatRepository { void configureSession({required Uri host, required String model, required InferenceOptions options, required Directory root, required AgentPermissions permissions}); Stream<ToolActivityEntity> get toolActivity; Future<Result<AgentTurnResult>> send(String message); void clearSession(); }`
- [ ] Passo 3: `workspace_repository.dart` — `abstract class WorkspaceRepository { Future<Result<List<WorkspaceTreeEntryEntity>>> listTree({required Directory root}); Future<Result<FilePreviewEntity>> readFile({required Directory root, required String path}); List<String> fileSuggestions({required Directory root, required String input, required int cursor, int limit}); String insertMention({required Directory root, required String input, required int cursor, required String path}); }` (os dois últimos métodos são síncronos — portam `desktop_controller.dart:524-535`, sem I/O)
- [ ] Verificação: `cd app && flutter analyze lib/domain/` sem erros

### Fase 3 — DataSources

- [ ] Passo 1: `ollama_remote_datasource.dart` — construtor recebe uma factory de `OllamaClient` (mesmo padrão de `OllamaClientFactory` em `desktop_controller.dart:15-20`, injetável para teste); métodos recriam o client por chamada com `host`/`model`/`options`, espelhando `_performConnect`/`selectModel`/`startModel` atuais
- [ ] Passo 2: `chat_agent_datasource.dart` — mantém internamente uma `AgentSession?`; `configureSession` a reconstrói (porta `_rebuildSession()` de `desktop_controller.dart:640-656`, incluindo o callback `onToolResult` alimentando um `StreamController<ToolActivityEntity>` broadcast); `send` delega a `sendDetailed`
- [ ] Passo 3: `workspace_datasource.dart` — mantém `FileMentionService`/`ToolRegistry` reconstruídos por `root` (porta `_resetWorkspaceContext()`); `listTree` porta `_visitDirectory` (`desktop_controller.dart:697-743`, `followLinks: false`, ignora `FileMentionService.ignoredDirectories`); `readFile` chama `ToolRegistry.execute(ToolCall(name: 'read_file', ...))` com `AgentPermissions.readOnly`
- [ ] Verificação: `cd app && flutter analyze lib/data/datasources/` sem erros

### Fase 4 — RepositoryImpl (fazendo os testes da Fase 1 passarem)

- [ ] Passo 1: `ollama_repository_impl.dart` com `RepositoryErrorMapper`-equivalente local: `try/catch (error, stackTrace)` em cada método, classificando `SocketException` → `NetworkException`, `OllamaException` → `OllamaServerException`, lista de modelos vazia → `OllamaServerException` (porta a regra de `desktop_controller.dart:595-599`)
- [ ] Passo 2: `chat_repository_impl.dart` — delega ao `ChatAgentDataSource`, classifica `AgentException` → `AgentFailureException`, `SocketException`/`OllamaException` → os mesmos tipos do passo anterior; `toolActivity` repassa o stream do DataSource sem transformação
- [ ] Passo 3: `workspace_repository_impl.dart` — classifica resultado `ERRO:` do `ToolRegistry` em `FileSystemFailureException` preservando a mensagem (porta `desktop_controller.dart:771-774`)
- [ ] Passo 4: Rodar os testes da Fase 1 contra as implementações reais
- [ ] Verificação: `cd app && flutter test test/data/` passa

### Fase 5 — DesktopStorageService e SystemMemoryService

- [ ] Passo 1: Mover `app/lib/src/desktop/desktop_state_store.dart` para `app/lib/common/services/desktop_storage_service.dart`; renomear `DesktopStateStore` → `DesktopStorageService`; trocar `DesktopPersistedState`/`PersistedSessionSummary` internos pelas entidades `DesktopPreferencesEntity`/`PersistedSessionSummaryEntity` da Parte 1 nas assinaturas de `load()`/`save()`, mantendo `_fromJson`/`_toJson` como estão (mesma lógica de leitura defensiva e gravação atômica)
- [ ] Passo 2: Mover `app/test/desktop_state_store_test.dart` para `app/test/common/services/desktop_storage_service_test.dart`, ajustando só os nomes de classe/tipo — os casos de teste (arquivo ausente, versão desconhecida, gravação atômica, normalização de recentes/sessões) continuam os mesmos
- [ ] Passo 3: Mover `app/lib/src/desktop/system_memory.dart` para `app/lib/common/services/system_memory_service.dart` e `app/test/system_memory_test.dart` para `app/test/common/services/system_memory_service_test.dart`, sem alterar a implementação (`SystemMemoryReader` já segue o padrão de Service: dependências injetáveis via construtor)
- [ ] Verificação: `cd app && flutter test test/common/services/` passa

### Fase 6 — Checkpoint

- [ ] Checkpoint: commit das mudanças da parte ("domain: interfaces de repository; data: datasources/repositoryimpl/storage service") + resumo curto do que ficou pronto, seguindo direto para a Parte 3

## Critérios de Sucesso

- [ ] As 3 interfaces de Repository criadas em `domain/interfaces/`, retornando `Result<T>`, sem import de infraestrutura
- [ ] Os 3 DataSources encapsulam as classes do pacote `salvador_cli` sem tratar erros (erro propaga para o RepositoryImpl)
- [ ] Os 3 RepositoryImpl classificam toda falha em `AppException` com `try/catch (error, stackTrace)`
- [ ] `DesktopStorageService`/`SystemMemoryService` relocados para `common/services/` com o mesmo comportamento observável de antes
- [ ] Build sem erros
- [ ] Todos os testes unitários da parte passando (RepositoryImpl com fakes + services movidos)

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| `ChatAgentDataSource` vazar o histórico de conversa da `AgentSession` entre trocas de pasta/modelo, já que agora vive num DataSource de longa duração em vez de um campo do `DesktopController` recriado a cada `selectRoot`/`selectModel` | Média | `configureSession` sempre descarta a `AgentSession` anterior e cria uma nova, replicando exatamente `_rebuildSession()` — testar explicitamente na Fase 1 que uma segunda chamada a `configureSession` limpa o histórico |
| Mover `desktop_state_store.dart`/`system_memory.dart` quebrar imports em `desktop_controller.dart`/`salvador_desktop_app.dart`, que ainda os referenciam nesta parte (só são removidos na Parte 6) | Alta | Atualizar os imports desses dois arquivos legados para o novo caminho em `common/services/` como parte do Passo 1/3 da Fase 5 — o app continua compilando com o `DesktopController` antigo até a Parte 6 |

## Rollback

`git revert` do commit desta parte. `DesktopController` continua sendo a única coisa que a UI usa (a Fase 5 só atualiza os imports dele para o novo local dos services); reverter volta `desktop_state_store.dart`/`system_memory.dart` ao lugar original sem quebrar nada.
