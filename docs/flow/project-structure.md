---
generated_at: 2026-08-28
source_commit: feb38f7
source_state: clean
verified_at: 2026-08-28
status: current
related_plans: []
---

# Estrutura do Projeto: Leve CLI (salvador_cli)

> **Resumo:** Agente de código 100% local escrito em Dart puro, que conversa com modelos servidos pelo Ollama via `/api/chat` e executa tool calls de arquivo e shell restritas a uma raiz; o pacote `salvador_cli` concentra toda a lógica e é consumido por dois frontends — a CLI interativa em `bin/` e o app Flutter desktop em `app/`.

## Stack e Tecnologias

| Elemento | Valor |
|----------|-------|
| Linguagem | Dart (SDK `^3.12.2`) |
| Framework | Nenhum na lib/CLI (`dart:io` + `dart:convert` puros); Flutter/Material 3 apenas em `app/` |
| Gerenciador de pacotes | pub |
| Principais dependências | Runtime: nenhuma (`dependencies: {}` em `pubspec.yaml`). Dev: `lints ^6.0.0`, `test ^1.25.6`. Em `app/`: `flutter`, `salvador_cli` (path `..`), `flutter_lints ^6.0.0` |
| Dependência externa de runtime | Binário `ollama` no PATH e servidor Ollama em `http://127.0.0.1:11434` (padrão) |

## Arquitetura

Não há camadas formais (`domain`/`data`) nem injeção de dependência por container. A lógica vive em um pacote Dart plano (`lib/src/`), onde cada arquivo é um módulo com uma responsabilidade única, exportado por um único barrel `lib/salvador_cli.dart`. As dependências são injetadas por construtor com valores padrão — `OllamaClient` aceita um `HttpClient`, `OllamaDiscovery` aceita um `OllamaProcessRunner`, `TerminalInput` aceita um `Stream<List<int>>` de entrada — o que torna cada módulo testável sem processo ou rede reais.

O `AgentSession` é o núcleo: mantém o histórico de `AgentMessage`, chama a interface `ChatClient` e, enquanto a resposta contiver `tool_calls`, executa cada uma pelo `ToolRegistry` e realimenta o histórico com mensagens de `role: 'tool'`, até o modelo responder sem ferramentas ou atingir `maxToolRounds` (padrão 8).

```
bin/salvador_cli.dart ─┐
                       ├─→ AgentSession ─→ ChatClient (OllamaClient) ─→ HTTP /api/chat
app/lib/…/DesktopController ─┘        └─→ ToolRegistry ─→ WorkspaceTool (filesystem / Process)

OllamaDiscovery ─→ Process.run('ollama list')   (antes da sessão, para listar modelos)
FileMentionService ─→ expande @caminho no prompt e sugere arquivos
```

### Regras de dependência

- `lib/src/` não importa Flutter — o pacote é Dart puro e roda em CLI e desktop sem alteração.
- Frontends (`bin/`, `app/`) importam apenas o barrel `package:salvador_cli/salvador_cli.dart`, nunca arquivos de `lib/src/` diretamente.
- `app/` depende de `salvador_cli` por caminho (`path: ..`); a dependência nunca é invertida.
- Toda operação de arquivo passa por `WorkspaceTool.resolveFile`, que resolve symlinks e rejeita caminhos fora da raiz.

## Features

| Feature | Caminho principal | Descrição resumida |
|---------|------------------|-------------------|
| Loop do agente | `lib/src/agent.dart` | `AgentSession` mantém o histórico, roda o ciclo de tool calling e devolve `AgentTurnResult` com resposta, métricas, arquivos mencionados e avisos |
| Cliente Ollama | `lib/src/ollama_client.dart` | Interface `ChatClient` e implementação `OllamaClient`: POST `/api/chat` com `stream: false`, `temperature: 0.1` e as definições de ferramentas |
| Descoberta do Ollama | `lib/src/ollama_discovery.dart` | Verifica se o binário existe (`ollama --help`) e lista modelos parseando a saída de `ollama list` |
| Ferramentas de workspace | `lib/src/tools.dart` | `ToolRegistry` com `read_file`, `write_file`, `replace_in_file` e `run_command`, todas confinadas à raiz |
| Menções de arquivo (`@`) | `lib/src/file_mentions.dart` | Indexa arquivos do projeto para autocomplete e injeta o conteúdo dos arquivos mencionados no prompt |
| Editor de linha do terminal | `lib/src/terminal_input.dart` | Editor sem dependências com menu inline de autocomplete para `@arquivo` e comandos `/` (setas + `Tab`) |
| Configuração da CLI | `lib/src/config.dart` | `CliConfig.parse` lê `--model`, `--host`, `--root`, `-h/--help` e as variáveis `OLLAMA_MODEL`/`OLLAMA_HOST` |
| CLI interativa | `bin/salvador_cli.dart` | Ponto de entrada: valida o Ollama, oferece a seleção de modelo e roda o chat com `/clear`, `/exit` e `/quit` |
| App desktop | `app/lib/src/desktop/` | Interface Flutter para a mesma sessão: `DesktopController` (`ChangeNotifier`) + `SalvadorDesktopApp` com painel de sessão, chat e atividades de ferramentas |

## Camadas / Módulos Compartilhados

| Tipo | Caminho | Responsabilidade |
|------|---------|-----------------|
| Barrel público | `lib/salvador_cli.dart` | Único ponto de importação do pacote; reexporta os nove módulos de `lib/src/` |
| Modelos e serialização | `lib/src/models.dart` | `AgentMessage`, `ToolCall`, `ToolDefinition`, `InferenceMetrics` e `formatInferenceMetrics` |
| System prompt | `lib/src/prompt.dart` | `systemPrompt`: sete linhas, dimensionado para modelos pequenos; o caminho da raiz é anexado pelo `AgentSession` |
| Testes do pacote | `test/` | `salvador_cli_test.dart`, `ollama_client_test.dart`, `ollama_discovery_test.dart`, `file_mentions_test.dart`, `terminal_input_test.dart` |
| Testes do app | `app/test/desktop_controller_test.dart` | Cobre o `DesktopController` |
| Runners nativos | `app/macos/`, `app/linux/`, `app/windows/` | Projetos de plataforma gerados pelo Flutter |

## Configuração

| Componente | Arquivo | Responsabilidade |
|-----------|---------|-----------------|
| Manifesto do pacote | `pubspec.yaml` | Nome `salvador_cli`, versão `0.1.0`, SDK `^3.12.2`, sem dependências de runtime |
| Manifesto do app | `app/pubspec.yaml` | `salvador_desktop`, `publish_to: none`, depende de `salvador_cli` por caminho |
| Análise estática | `analysis_options.yaml` | `include: package:lints/recommended.yaml` |
| Análise estática do app | `app/analysis_options.yaml` | Regras do `flutter_lints` |
| Parsing de argumentos | `lib/src/config.dart` | Faz o parsing manual dos flags e valida host e raiz antes de qualquer chamada |
| Bootstrap da CLI | `bin/salvador_cli.dart` | Encadeia config → discovery → seleção de modelo → chat; usa códigos de saída `64` (uso inválido) e `69` (Ollama indisponível) |
| Bootstrap do desktop | `app/lib/main.dart` | `WidgetsFlutterBinding.ensureInitialized()` e `runApp(SalvadorDesktopApp())` |
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

- **`run_command` não é sandbox.** O `RunCommandTool` roda `/bin/sh -lc` (ou `cmd.exe /c` no Windows) com as permissões do usuário, apenas com `workingDirectory` na raiz e timeout de 30 segundos. O confinamento à raiz vale para as ferramentas de arquivo, não para o processo filho.
- **Limites embutidos:** `read_file` trunca em 100.000 caracteres, `run_command` em 20.000, arquivos mencionados com `@` em 512 KiB, e o loop do agente para em 8 rodadas de ferramentas.
- **Comandos slash são do frontend.** `/clear`, `/exit` e `/quit` são tratados em `bin/salvador_cli.dart`; o `DesktopController` reconhece apenas `/clear`. Nenhum deles chega ao modelo.
- **Divergência intencional na descoberta do Ollama:** a CLI usa `Process.run('ollama', …)` direto, enquanto o app desktop injeta `_runOllamaProcess`, que tenta caminhos absolutos conhecidos (`/opt/homebrew/bin`, `/usr/local/bin`, `%LOCALAPPDATA%\Programs\Ollama`) porque um app com GUI não herda o `PATH` do shell.
- **Acentuação:** os textos de `lib/` e `bin/` são escritos sem acentos; `app/` usa acentuação completa. A divergência já existe no código.
- **`docs/plan/` ainda não existe**, por isso `related_plans` está vazio.
- O documento `leve-cli.md` na raiz é o brainstorming original do produto e ainda lista suposições em aberto (compatibilidade com llama.cpp, por exemplo) que o código atual não implementa — só o Ollama é suportado.
