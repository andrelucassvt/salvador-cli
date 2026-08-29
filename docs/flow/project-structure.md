---
generated_at: 2026-08-29
source_commit: cd04dea
source_state: dirty
verified_at: 2026-08-29
status: current
related_plans:
  - 'docs/plan/salvador-desktop-redesign/00-indice.md'
  - 'docs/plan/context-files-skills.md'
  - 'docs/plan/attach-files-desktop.md'
---

# Estrutura do Projeto: Leve CLI (salvador_cli)

> **Resumo:** Agente de código 100% local escrito em Dart puro, que conversa com modelos servidos pelo Ollama via `/api/chat` e executa tool calls de arquivo e shell restritas a uma raiz; o pacote `salvador_cli` concentra toda a lógica e é consumido por dois frontends — a CLI interativa em `bin/` e o app Flutter desktop em `app/`.

## Stack e Tecnologias

| Elemento | Valor |
|----------|-------|
| Linguagem | Dart (SDK `^3.12.2`) |
| Framework | Nenhum na lib/CLI (`dart:io` + `dart:convert` puros); Flutter/Material 3 apenas em `app/` |
| Gerenciador de pacotes | pub |
| Principais dependências | Runtime: nenhuma (`dependencies: {}` em `pubspec.yaml`). Dev: `lints ^6.0.0`, `test ^1.25.6`. Em `app/`: `flutter`, `salvador_cli` (path `..`), `flutter_bloc ^9.1.1`, `get_it ^9.2.1`, `file_selector ^1.1.0`, `window_manager ^0.5.2`, `flutter_markdown_plus ^1.0.12`, `url_launcher ^6.3.2`; dev: `flutter_lints ^6.0.0`, `bloc_test ^10.0.0`, `mocktail ^1.0.5`, `checks ^0.3.1` |
| Dependência externa de runtime | Binário `ollama` no PATH e servidor Ollama em `http://127.0.0.1:11434` (padrão) |

## Arquitetura

Não há camadas formais (`domain`/`data`) nem injeção de dependência por container. A lógica vive em um pacote Dart plano (`lib/src/`), onde cada arquivo é um módulo com uma responsabilidade única, exportado por um único barrel `lib/salvador_cli.dart`. As dependências são injetadas por construtor com valores padrão — `OllamaClient` aceita um `HttpClient`, `OllamaDiscovery` aceita um `OllamaProcessRunner`, `TerminalInput` aceita um `Stream<List<int>>` de entrada, `AgentSession` aceita um `ContextFilesService` opcional — o que torna cada módulo testável sem processo ou rede reais. No desktop, os datasources recebem uma `OllamaClientFactory` para criar clientes HTTP sem acoplar o pacote.

O `AgentSession` é o núcleo: mantém o histórico de `AgentMessage`, chama a interface `ChatClient` e, enquanto a resposta contiver `tool_calls`, executa cada uma pelo `ToolRegistry` e realimenta o histórico com mensagens de `role: 'tool'`, até o modelo responder sem ferramentas ou atingir `maxToolRounds` (padrão 8).

```
bin/salvador_cli.dart ─┐
                        ├─→ AgentSession ─→ ChatClient (OllamaClient) ─→ HTTP /api/chat
app/lib/…/desktop_view.dart ─┘        └─→ ToolRegistry ─→ WorkspaceTool (filesystem / Process)
                                                          └─→ UseSkillTool ─→ ContextFilesService

OllamaDiscovery ─→ Process.run('ollama list')   (só na CLI, antes da sessão, para listar modelos)
WorkspaceCubit ─→ OllamaRepository ─→ OllamaRemoteDataSource ─→ OllamaClient ─→ /api/tags, /api/ps, /api/show, /api/generate, /api/version
ContextFilesService ─→ descobre .agents/skills/*/SKILL.md, injeta o AGENTS.md da raiz no system prompt e alimenta a tool use_skill
FileMentionService ─→ expande @caminho no prompt, sugere arquivos e compartilha ignoredDirectories com a árvore do desktop
FileAttachmentService ─→ lê anexos escolhidos no picker; imagens viram base64 no campo images de AgentMessage
DesktopStorageService ─→ JSON versionado no diretório de dados do SO (preferências, recentes, resumos de sessões)
```

### Regras de dependência

- `lib/src/` não importa Flutter — o pacote é Dart puro e roda em CLI e desktop sem alteração.
- Frontends (`bin/`, `app/`) importam apenas o barrel `package:salvador_cli/salvador_cli.dart`, nunca arquivos de `lib/src/` diretamente.
- `app/` depende de `salvador_cli` por caminho (`path: ..`); a dependência nunca é invertida.
- Toda operação de arquivo passa por `WorkspaceTool.resolveFile`, que resolve symlinks e rejeita caminhos fora da raiz.

## Features

| Feature | Caminho principal | Descrição resumida |
|---------|------------------|-------------------|
| Loop do agente | `lib/src/agent.dart` | `AgentSession` mantém o histórico, roda o ciclo de tool calling e devolve `AgentTurnResult` com resposta, métricas, arquivos mencionados e avisos; aceita `AgentPermissions`, `ToolResultObserver`, `ContextFilesService` (anexa o `AGENTS.md` da raiz ao system prompt) e `images` por mensagem |
| Cliente Ollama | `lib/src/ollama_client.dart` | Interface `ChatClient` e implementação `OllamaClient`: `/api/chat` (`stream: false`, `InferenceOptions`), `/api/tags`, `/api/ps`, `/api/show`, `/api/generate` (load/unload) e `/api/version` (testConnection) |
| Descoberta do Ollama | `lib/src/ollama_discovery.dart` | Verifica se o binário existe (`ollama --help`) e lista modelos parseando a saída de `ollama list` — usada apenas pela CLI |
| Ferramentas de workspace | `lib/src/tools.dart` | `ToolRegistry` com `read_file`, `write_file`, `replace_in_file` e `run_command`, confinadas à raiz e filtradas por `AgentPermissions`; com `ContextFilesService`, registra também a tool `use_skill`; leitura rejeita binário/UTF-8 inválido |
| Contexto de arquivos | `lib/src/context_files.dart` | `ContextFilesService` descobre skills em `.agents/skills/*/SKILL.md` (`SkillInfo` com `description:` do frontmatter), injeta o `AGENTS.md` da raiz no system prompt, expande menções `/skill` no prompt e fornece conteúdo à tool `use_skill`; limites de 64 KiB e confinamento por symlink próprio |
| Menções de arquivo (`@`) | `lib/src/file_mentions.dart` | Indexa arquivos do projeto para autocomplete e injeta o conteúdo dos arquivos mencionados no prompt; `ignoredDirectories` é público para o painel de arquivos |
| Editor de linha do terminal | `lib/src/terminal_input.dart` | Editor sem dependências com menu inline de autocomplete para `@arquivo` e comandos `/` (setas + `Tab`) |
| Configuração da CLI | `lib/src/config.dart` | `CliConfig.parse` lê `--model`, `--host`, `--root`, `--no-context`, `-h/--help` e as variáveis `OLLAMA_MODEL`/`OLLAMA_HOST` |
| CLI interativa | `bin/salvador_cli.dart` | Ponto de entrada: valida o Ollama, oferece a seleção de modelo e roda o chat com `/clear`, `/exit`, `/quit` e comandos `/skill` gerados das skills descobertas |
| App desktop | `app/lib/presentation/desktop/` | Clean Architecture com GetIt (`AppInjector`): `WorkspaceCubit`/`ChatCubit`/`FileExplorerCubit`/`SettingsCubit` orquestram conexão HTTP, carga de modelos, configurações, atividade/sessões, árvore/preview e anexos; `DesktopView` (em `view/`) desenha o shell (top bar, painéis com rails, modal, composer, markdown) |

## Camadas / Módulos Compartilhados

| Tipo | Caminho | Responsabilidade |
|------|---------|-----------------|
| Barrel público | `lib/salvador_cli.dart` | Único ponto de importação do pacote; reexporta os dez módulos de `lib/src/` |
| Modelos e serialização | `lib/src/models.dart` | `AgentMessage`, `ToolCall`, `ToolDefinition`, `InferenceMetrics`, `InferenceOptions`, `OllamaModelInfo`, `OllamaRunningModel` e `formatInferenceMetrics` |
| System prompt | `lib/src/prompt.dart` | `systemPrompt`: sete linhas, dimensionado para modelos pequenos; o caminho da raiz e o `AGENTS.md` são anexados pelo `AgentSession` |
| Contexto de arquivos | `lib/src/context_files.dart` | `SkillInfo` + `ContextFilesService`: `discoverSkills()`, `agentsMdContext()`, `expand()` (`/skill`) e `skillContent()` para a tool `use_skill`; confinamento por symlink e limites de 64 KiB |
| Estado persistido do desktop | `app/lib/common/services/desktop_storage_service.dart` | Serialização JSON versionada de `DesktopPreferencesEntity`/`PersistedSessionSummary` (inclui `context_files_enabled`) com leitura defensiva e gravação atômica |
| Anexos do desktop | `app/lib/common/services/file_attachment_service.dart` | `FileAttachmentService`: lê anexo escolhido no picker — imagem (base64 + mime, até 8 MiB) ou texto (até 512 KiB, rejeita binário/UTF-8 inválido); caminho não precisa estar na raiz, a escolha foi explícita do usuário |
| Memória do sistema | `app/lib/common/services/system_memory_service.dart` | `SystemMemoryReader`: RAM disponível por plataforma com runner injetável |
| Formatação do desktop | `app/lib/common/utils/formatters.dart` | Helpers de formatação compartilhados entre views |
| Arquitetura do app | `app/lib/config/inject/app_injector.dart`, `app/lib/domain/`, `app/lib/data/`, `app/lib/config/error/` | GetIt registra services → datasources → repositories → cubits; entidades e contratos de Repository no domínio; datasources/repos com `Result<T>` e `AppException`; datasources encapsulam o pacote (`OllamaRemoteDataSource`/`ChatAgentDataSource` com `OllamaClientFactory` injetável) |
| Apresentação do app | `app/lib/presentation/desktop/` | `view/` (`DesktopView`, shell) + `view_model/` (`WorkspaceCubit`/`ChatCubit`/`FileExplorerCubit`/`SettingsCubit`) + `content/`, `widgets/` e `theme/` |
| Testes do pacote | `test/` | `salvador_cli_test.dart`, `config_test.dart`, `context_files_test.dart`, `ollama_client_test.dart`, `ollama_discovery_test.dart`, `file_mentions_test.dart`, `terminal_input_test.dart` |
| Testes do app | `app/test/` | Cubits com fakes de Repository (`presentation/desktop/fakes/`), RepositoryImpl com fakes de DataSource (`data/chat/`, `data/ollama/`, `data/workspace/`), entidades/erros (`domain/entities/`, `config/error/`), services (`common/services/`) e `salvador_desktop_app_test.dart` (widget tests do shell) |
| Runners nativos | `app/macos/`, `app/linux/`, `app/windows/` | Projetos de plataforma gerados pelo Flutter |

## Configuração

| Componente | Arquivo | Responsabilidade |
|-----------|---------|-----------------|
| Manifesto do pacote | `pubspec.yaml` | Nome `salvador_cli`, versão `0.1.0`, SDK `^3.12.2`, sem dependências de runtime |
| Manifesto do app | `app/pubspec.yaml` | `salvador_desktop`, `publish_to: none`, depende de `salvador_cli` por caminho e declara `file_selector`, `window_manager`, `flutter_markdown_plus`, `url_launcher` e as fontes OFL empacotadas |
| Análise estática | `analysis_options.yaml` | `include: package:lints/recommended.yaml` |
| Análise estática do app | `app/analysis_options.yaml` | Regras do `flutter_lints` |
| Parsing de argumentos | `lib/src/config.dart` | Faz o parsing manual dos flags e valida host e raiz antes de qualquer chamada |
| Bootstrap da CLI | `bin/salvador_cli.dart` | Encadeia config → discovery → seleção de modelo → chat; usa códigos de saída `64` (uso inválido) e `69` (Ollama indisponível) |
| Bootstrap do desktop | `app/lib/main.dart` | `WidgetsFlutterBinding.ensureInitialized()` + `AppInjector.setupDependencies()` e `runApp(const DesktopView())`; no macOS, configura o `window_manager` com title bar oculta |
| Tema do desktop | `app/lib/presentation/desktop/theme/desktop_theme.dart` | Paleta fixa (navy/ocean/coral/shell/paper/…) e dimensões do shell; `DesktopView` monta o `ThemeData` Material 3 a partir desses tokens |
| Sincronização de skills | `sync-brain.sh` | Baixa as skills Brain Flows e os agentes de `andrelucassvt/brain-flows` para `.claude/skills/`, `.agents/skills/` e `.claude/agents/` |

## Dependências Externas Principais

| Pacote | Versão | Uso no projeto |
|--------|--------|---------------|
| `lints` | ^6.0.0 | Regras de análise estática do pacote Dart |
| `test` | ^1.25.6 | Testes do pacote (`dart test`) |
| `flutter` | SDK | UI do app desktop |
| `flutter_lints` | ^6.0.0 | Regras de análise estática do app |
| `salvador_cli` | path `..` | O app desktop consome a lógica do agente do pacote raiz |
| `flutter_bloc` | ^9.1.1 | Cubits/estados do app desktop |
| `get_it` | ^9.2.1 | DI do app desktop (`AppInjector`) |
| `file_selector` | ^1.1.0 | Picker nativo de pasta no app desktop |
| `window_manager` | ^0.5.2 | Title bar oculta no macOS |
| `flutter_markdown_plus` | ^1.0.12 | Renderização Markdown das respostas do agente no chat |
| `url_launcher` | ^6.3.2 | Abertura de links externos no desktop |

## Observações

- **`run_command` não é sandbox.** O `RunCommandTool` roda `/bin/sh -lc` (ou `cmd.exe /c` no Windows) com as permissões do usuário, apenas com `workingDirectory` na raiz e timeout de 30 segundos. O confinamento à raiz vale para as ferramentas de arquivo, não para o processo filho. No desktop, o toggle “Acesso à rede” fica desligado/indisponível por isso.
- **Limites embutidos:** `read_file` trunca em 100.000 caracteres, `run_command` em 20.000, arquivos mencionados com `@` em 512 KiB, `AGENTS.md` em 64 KiB (rejeitado se maior), skill em 64 KiB truncada com `[TRUNCADO]`, imagem anexada no desktop até 8 MiB, e o loop do agente para em 8 rodadas de ferramentas. `read_file` rejeita binário (byte NUL) e UTF-8 inválido com `ERRO:`.
- **Comandos slash e skills.** `/clear`, `/exit` e `/quit` são tratados no frontend e nunca chegam ao modelo: em `bin/salvador_cli.dart` e no desktop em `_ShellScreenState._send` (`view/desktop_view.dart`, `/exit`/`/quit` com `SystemNavigator.pop()`). Já as menções `/skill` são expandidas em contexto por `ContextFilesService` (CLI e desktop) antes de virar prompt, e o modelo também pode buscar skills sozinho pela tool `use_skill`.
- **Descoberta do Ollama só na CLI.** O desktop resolve tudo por HTTP (`/api/tags`, `/api/ps`, `/api/show`, `/api/generate`, `/api/version`) via `OllamaRemoteDataSource`/`OllamaRepositoryImpl` e não invoca o binário; só a CLI usa `OllamaDiscovery` (`Process.run('ollama ...')`).
- **Skills só em `.agents/skills/`.** `ContextFilesService` lê apenas `.agents/skills/*/SKILL.md`; `.claude/skills/` existe para os agentes Claude e é mantido sincronizado por `sync-brain.sh`, mas não alimenta `/skill` nem `use_skill`.
- **Acentuação:** os textos de `lib/` e `bin/` são escritos sem acentos; `app/` usa acentuação completa. A divergência já existe no código.
- O documento `leve-cli.md` na raiz é o brainstorming original do produto e ainda lista suposições em aberto (compatibilidade com llama.cpp, por exemplo) que o código atual não implementa — só o Ollama é suportado.
