---
generated_at: 2026-08-28
source_commit: 9c08a3d
source_state: clean
verified_at: 2026-08-28
status: current
related_plans: ['docs/plan/salvador-desktop-redesign/00-indice.md']
---

# Estrutura do Projeto: Leve CLI (salvador_cli)

> **Resumo:** Agente de código 100% local escrito em Dart puro, que conversa com modelos servidos pelo Ollama via `/api/chat` e executa tool calls de arquivo e shell restritas a uma raiz; o pacote `salvador_cli` concentra toda a lógica e é consumido por dois frontends — a CLI interativa em `bin/` e o app Flutter desktop em `app/`.

## Stack e Tecnologias

| Elemento | Valor |
|----------|-------|
| Linguagem | Dart (SDK `^3.12.2`) |
| Framework | Nenhum na lib/CLI (`dart:io` + `dart:convert` puros); Flutter/Material 3 apenas em `app/` |
| Gerenciador de pacotes | pub |
| Principais dependências | Runtime: nenhuma (`dependencies: {}` em `pubspec.yaml`). Dev: `lints ^6.0.0`, `test ^1.25.6`. Em `app/`: `flutter`, `salvador_cli` (path `..`), `flutter_lints ^6.0.0`, `file_selector ^1.1.0`, `window_manager ^0.5.2` |
| Dependência externa de runtime | Binário `ollama` no PATH e servidor Ollama em `http://127.0.0.1:11434` (padrão) |

## Arquitetura

Não há camadas formais (`domain`/`data`) nem injeção de dependência por container. A lógica vive em um pacote Dart plano (`lib/src/`), onde cada arquivo é um módulo com uma responsabilidade única, exportado por um único barrel `lib/salvador_cli.dart`. As dependências são injetadas por construtor com valores padrão — `OllamaClient` aceita um `HttpClient`, `OllamaDiscovery` aceita um `OllamaProcessRunner`, `TerminalInput` aceita um `Stream<List<int>>` de entrada — o que torna cada módulo testável sem processo ou rede reais.

O `AgentSession` é o núcleo: mantém o histórico de `AgentMessage`, chama a interface `ChatClient` e, enquanto a resposta contiver `tool_calls`, executa cada uma pelo `ToolRegistry` e realimenta o histórico com mensagens de `role: 'tool'`, até o modelo responder sem ferramentas ou atingir `maxToolRounds` (padrão 8).

```
bin/salvador_cli.dart ─┐
                        ├─→ AgentSession ─→ ChatClient (OllamaClient) ─→ HTTP /api/chat
app/lib/…/DesktopController ─┘        └─→ ToolRegistry ─→ WorkspaceTool (filesystem / Process)

OllamaDiscovery ─→ Process.run('ollama list')   (só na CLI, antes da sessão, para listar modelos)
DesktopController ─→ OllamaClient ─→ /api/tags, /api/ps, /api/show, /api/generate, /api/version
FileMentionService ─→ expande @caminho no prompt, sugere arquivos e compartilha ignoredDirectories com a árvore do desktop
DesktopStateStore ─→ JSON versionado no diretório de dados do SO (preferências, recentes, resumos de sessões)
```

### Regras de dependência

- `lib/src/` não importa Flutter — o pacote é Dart puro e roda em CLI e desktop sem alteração.
- Frontends (`bin/`, `app/`) importam apenas o barrel `package:salvador_cli/salvador_cli.dart`, nunca arquivos de `lib/src/` diretamente.
- `app/` depende de `salvador_cli` por caminho (`path: ..`); a dependência nunca é invertida.
- Toda operação de arquivo passa por `WorkspaceTool.resolveFile`, que resolve symlinks e rejeita caminhos fora da raiz.

## Features

| Feature | Caminho principal | Descrição resumida |
|---------|------------------|-------------------|
| Loop do agente | `lib/src/agent.dart` | `AgentSession` mantém o histórico, roda o ciclo de tool calling e devolve `AgentTurnResult` com resposta, métricas, arquivos mencionados e avisos; aceita `AgentPermissions` e `ToolResultObserver` |
| Cliente Ollama | `lib/src/ollama_client.dart` | Interface `ChatClient` e implementação `OllamaClient`: `/api/chat` (`stream: false`, `InferenceOptions`), `/api/tags`, `/api/ps`, `/api/show`, `/api/generate` (load/unload) e `/api/version` (testConnection) |
| Descoberta do Ollama | `lib/src/ollama_discovery.dart` | Verifica se o binário existe (`ollama --help`) e lista modelos parseando a saída de `ollama list` — usada apenas pela CLI |
| Ferramentas de workspace | `lib/src/tools.dart` | `ToolRegistry` com `read_file`, `write_file`, `replace_in_file` e `run_command`, confinadas à raiz e filtradas por `AgentPermissions`; leitura rejeita binário/UTF-8 inválido |
| Menções de arquivo (`@`) | `lib/src/file_mentions.dart` | Indexa arquivos do projeto para autocomplete e injeta o conteúdo dos arquivos mencionados no prompt; `ignoredDirectories` é público para o painel de arquivos |
| Editor de linha do terminal | `lib/src/terminal_input.dart` | Editor sem dependências com menu inline de autocomplete para `@arquivo` e comandos `/` (setas + `Tab`) |
| Configuração da CLI | `lib/src/config.dart` | `CliConfig.parse` lê `--model`, `--host`, `--root`, `-h/--help` e as variáveis `OLLAMA_MODEL`/`OLLAMA_HOST` |
| CLI interativa | `bin/salvador_cli.dart` | Ponto de entrada: valida o Ollama, oferece a seleção de modelo e roda o chat com `/clear`, `/exit` e `/quit` |
| App desktop | `app/lib/src/desktop/` | `DesktopController` (`ChangeNotifier`) orquestra conexão HTTP, carga/descarga de modelos, configurações, atividade/sessões e árvore/preview; `SalvadorDesktopApp` desenha o shell (top bar, painéis com rails, modal, composer) |

## Camadas / Módulos Compartilhados

| Tipo | Caminho | Responsabilidade |
|------|---------|-----------------|
| Barrel público | `lib/salvador_cli.dart` | Único ponto de importação do pacote; reexporta os nove módulos de `lib/src/` |
| Modelos e serialização | `lib/src/models.dart` | `AgentMessage`, `ToolCall`, `ToolDefinition`, `InferenceMetrics`, `InferenceOptions`, `OllamaModelInfo`, `OllamaRunningModel` e `formatInferenceMetrics` |
| System prompt | `lib/src/prompt.dart` | `systemPrompt`: sete linhas, dimensionado para modelos pequenos; o caminho da raiz é anexado pelo `AgentSession` |
| Estado persistido do desktop | `app/lib/src/desktop/desktop_state_store.dart` | `DesktopPersistedState`, `PersistedSessionSummary` e `DesktopStateStore`: JSON versionado com leitura defensiva e gravação atômica |
| Memória do sistema | `app/lib/src/desktop/system_memory.dart` | `SystemMemoryReader`: RAM disponível por plataforma com runner injetável |
| Testes do pacote | `test/` | `salvador_cli_test.dart`, `ollama_client_test.dart`, `ollama_discovery_test.dart`, `file_mentions_test.dart`, `terminal_input_test.dart` |
| Testes do app | `app/test/` | `desktop_controller_test.dart`, `desktop_state_store_test.dart`, `system_memory_test.dart` e `salvador_desktop_app_test.dart` (widget tests do shell) |
| Runners nativos | `app/macos/`, `app/linux/`, `app/windows/` | Projetos de plataforma gerados pelo Flutter |

## Configuração

| Componente | Arquivo | Responsabilidade |
|-----------|---------|-----------------|
| Manifesto do pacote | `pubspec.yaml` | Nome `salvador_cli`, versão `0.1.0`, SDK `^3.12.2`, sem dependências de runtime |
| Manifesto do app | `app/pubspec.yaml` | `salvador_desktop`, `publish_to: none`, depende de `salvador_cli` por caminho e declara `file_selector`, `window_manager` e as fontes OFL empacotadas |
| Análise estática | `analysis_options.yaml` | `include: package:lints/recommended.yaml` |
| Análise estática do app | `app/analysis_options.yaml` | Regras do `flutter_lints` |
| Parsing de argumentos | `lib/src/config.dart` | Faz o parsing manual dos flags e valida host e raiz antes de qualquer chamada |
| Bootstrap da CLI | `bin/salvador_cli.dart` | Encadeia config → discovery → seleção de modelo → chat; usa códigos de saída `64` (uso inválido) e `69` (Ollama indisponível) |
| Bootstrap do desktop | `app/lib/main.dart` | `WidgetsFlutterBinding.ensureInitialized()` e `runApp(SalvadorDesktopApp())`; no macOS, configura o `window_manager` com title bar oculta |
| Tema do desktop | `app/lib/src/desktop/salvador_desktop_app.dart` | Paleta fixa (navy/ocean/coral/shell) e `ThemeData` Material 3 declarados no topo do arquivo |
| Sincronização de skills | `sync-brain.sh` | Baixa as skills Brain Flows e os agentes de `andrelucassvt/brain-flows` para `.claude/skills/`, `.agents/skills/` e `.claude/agents/` |

## Dependências Externas Principais

| Pacote | Versão | Uso no projeto |
|--------|--------|---------------|
| `lints` | ^6.0.0 | Regras de análise estática do pacote Dart |
| `test` | ^1.25.6 | Testes do pacote (`dart test`) |
| `flutter` | SDK | UI do app desktop |
| `flutter_lints` | ^6.0.0 | Regras de análise estática do app |
| `salvador_cli` | path `..` | O app desktop consome a lógica do agente do pacote raiz |

## Observações

- **`run_command` não é sandbox.** O `RunCommandTool` roda `/bin/sh -lc` (ou `cmd.exe /c` no Windows) com as permissões do usuário, apenas com `workingDirectory` na raiz e timeout de 30 segundos. O confinamento à raiz vale para as ferramentas de arquivo, não para o processo filho. No desktop, o toggle “Acesso à rede” fica desligado/indisponível por isso.
- **Limites embutidos:** `read_file` trunca em 100.000 caracteres, `run_command` em 20.000, arquivos mencionados com `@` em 512 KiB, e o loop do agente para em 8 rodadas de ferramentas. `read_file` rejeita binário (byte NUL) e UTF-8 inválido com `ERRO:`.
- **Comandos slash são do frontend.** `/clear`, `/exit` e `/quit` são tratados em `bin/salvador_cli.dart`; o `DesktopController` reconhece apenas `/clear`. Nenhum deles chega ao modelo.
- **Descoberta do Ollama só na CLI.** O desktop resolve tudo por HTTP (`/api/tags`, `/api/ps`, `/api/version`) e não invoca o binário; o runner de caminhos absolutos (`/opt/homebrew/bin`, `/usr/local/bin`, `%LOCALAPPDATA%\Programs\Ollama`) saiu do `desktop_controller.dart` e permanece apenas no fluxo da CLI, onde `Process.run` precisa do PATH.
- **Acentuação:** os textos de `lib/` e `bin/` são escritos sem acentos; `app/` usa acentuação completa. A divergência já existe no código.
- O documento `leve-cli.md` na raiz é o brainstorming original do produto e ainda lista suposições em aberto (compatibilidade com llama.cpp, por exemplo) que o código atual não implementa — só o Ollama é suportado.
