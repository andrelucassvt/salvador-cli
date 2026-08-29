# Leve CLI (salvador_cli)

Agente de código 100% local em Dart puro, que conversa com modelos do Ollama e executa tool calls de arquivo e shell confinadas a uma raiz. Dois frontends consomem a mesma lógica: a CLI interativa em `bin/` e o app Flutter desktop em `app/`.

## Stack

- Dart SDK `^3.12.2`; o pacote raiz não tem nenhuma dependência de runtime (`dependencies: {}`)
- `dart:io` e `dart:convert` puros — sem `http`, sem `args`, sem gerador de código
- Flutter + Material 3 somente em `app/` (`salvador_desktop`, depende de `salvador_cli` por `path: ..`)
- Dependência externa: binário `ollama` no PATH e o servidor em `http://127.0.0.1:11434`

## Estrutura

- `lib/src/` — módulos planos, um por responsabilidade: `agent`, `config`, `context_files`, `file_mentions`, `models`, `ollama_client`, `ollama_discovery`, `prompt`, `terminal_input`, `tools`
- `lib/salvador_cli.dart` — barrel; único ponto de importação do pacote (exporta os dez módulos)
- `bin/salvador_cli.dart` — CLI interativa
- `app/lib/` — Clean Architecture (`common`, `config`, `data`, `domain`, `presentation`); `presentation/desktop/` tem `view/` (`DesktopView`, o shell), `view_model/` (cubits), `content/`, `widgets/` e `theme/`; `common/services/` tem armazenamento, anexos e memória do sistema
- `test/` — testes do pacote; `app/test/` — testes do app
- `docs/flow/` — documentação de fluxos; `docs/plan/` — planos de implementação

## Comandos

- `dart analyze` e `dart test` — validação do pacote (rode os dois antes de concluir)
- `dart run bin/salvador_cli.dart` — executa a CLI
- `cd app && flutter analyze && flutter test` — validação do app desktop
- `./sync-brain.sh` — atualiza as skills Brain Flows em `.claude/skills/` e `.agents/skills/` e os agentes locais em `.claude/agents/`

## Convenções

- `lib/src/` nunca importa Flutter: o pacote precisa continuar rodando em CLI e desktop sem alteração
- Frontends importam só `package:salvador_cli/salvador_cli.dart`; ao criar um módulo em `lib/src/`, exporte-o no barrel
- Dependências externas entram por construtor com padrão injetável — `HttpClient` em `OllamaClient`, `OllamaProcessRunner` em `OllamaDiscovery`, `Stream<List<int>>` em `TerminalInput`. É assim que os testes rodam sem rede nem processo real
- Toda leitura ou escrita de arquivo passa por `WorkspaceTool.resolveFile`, que resolve symlinks e rejeita caminhos fora da raiz. Não use `File(...)` direto em uma ferramenta nova
- Falha de ferramenta vira string `ERRO: <motivo>` devolvida ao modelo, nunca exceção propagada: o modelo precisa poder corrigir os argumentos e tentar de novo
- Erros esperados usam exceções próprias (`ToolException`, `AgentException`, `OllamaException`, `OllamaDiscoveryException`, `HelpRequested`, `TerminalInputInterrupted`), não `Exception` genérica
- Comandos slash (`/clear`, `/exit`, `/quit`) são tratados no frontend e nunca chegam ao modelo; menções `/skill` são expandidas em contexto por `ContextFilesService` antes de virar prompt
- Textos de `lib/` e `bin/` são escritos sem acentos; `app/` usa acentuação completa — siga o arquivo que estiver editando
- Mensagens ao usuário em português
- `ContextFilesService` descobre skills em `.agents/skills/*/SKILL.md` e injeta o `AGENTS.md` da raiz no system prompt; tudo ligado por um toggle único (`--no-context` na CLI, `contextFilesEnabled` no desktop)

## Gotchas

- **O system prompt é enxuto de propósito.** `lib/src/prompt.dart` tem sete linhas porque o alvo são modelos pequenos, onde prompt pesado derruba o tool-calling. Não o expanda sem necessidade comprovada
- **`run_command` não é sandbox:** roda `/bin/sh -lc` (ou `cmd.exe /c`) com as permissões do usuário; só o `workingDirectory` fica na raiz. O confinamento vale para as ferramentas de arquivo
- **Limites embutidos:** `read_file` trunca em 100.000 caracteres, `run_command` em 20.000, arquivo mencionado com `@` em 512 KiB, `AGENTS.md` em 64 KiB (rejeitado se maior), skill truncada em 64 KiB com `[TRUNCADO]`, loop do agente em 8 rodadas de ferramentas
- **O app desktop não executa o binário do Ollama:** resolve tudo por HTTP via `OllamaClient` (`/api/tags`, `/api/ps`, `/api/show`, `/api/generate`, `/api/version`); só a CLI usa `OllamaDiscovery` com `Process.run('ollama ...')`. Mudança na descoberta do Ollama precisa considerar os dois frontends
- **Códigos de saída da CLI:** `64` para uso inválido, `69` para Ollama indisponível
- **Skills só em `.agents/skills/`:** `ContextFilesService` não lê `.claude/skills/`; `sync-brain.sh` mantém os dois lugares sincronizados, mas só o primeiro alimenta `/skill` e a tool `use_skill`
- `leve-cli.md` é o brainstorming original e ainda cita suposições não implementadas (llama.cpp, por exemplo). Só o Ollama é suportado

## Não fazer

- Não adicione dependências de runtime ao `pubspec.yaml` raiz sem pedido explícito — o pacote sem dependências é uma decisão de projeto
- Não faça o app desktop importar arquivos de `lib/src/` diretamente
- Não introduza streaming na chamada `/api/chat` sem pedido: `stream: false` é premissa do parsing atual e do cálculo de métricas
- Não edite os projetos nativos gerados em `app/macos/`, `app/linux/` e `app/windows/` manualmente
- Não edite `.claude/skills/`, `.agents/skills/` nem `.claude/agents/` à mão: são sincronizados por `sync-brain.sh`

## 📖 Documentação de Flows

Para qualquer feature ou fluxo, verifique a pasta `./docs/flow/`: leia os títulos dos arquivos `.md` disponíveis e, se algum for relevante para a tarefa atual, leia-o antes de implementar ou debugar. Invoque a skill `flow` para criar ou atualizar flows individuais.

## 🧪 Teste funcional

Após implementar, não execute o projeto para validar o resultado (rodar o app, emulador/simulador, dispositivo físico, servidor local, screenshots ou interação simulada). Teste funcional/visual é responsabilidade do usuário.

- Limite a verificação a análise estática, build/compile e testes automatizados
- Ao concluir, liste objetivamente o que o usuário deve testar manualmente
- Não pergunte se deve executar o projeto — só faça isso se o usuário pedir explicitamente
