---
generated_at: 2026-08-28
source_commit: ae9aaaa
source_state: dirty
verified_at: 2026-08-28
status: current
related_plans: []
---

# Sugestões de Flows a Documentar

> Gerado em 2026-08-28. Invoque a skill `flow` para criar qualquer um destes flows.

## Flows Sugeridos

### Loop do agente
**Arquivo a criar:** `docs/flow/loop-do-agente.md`
**Resumo:** Da chamada `AgentSession.sendDetailed` até a resposta final: expansão de menções, envio ao `ChatClient`, execução das `tool_calls` pelo `ToolRegistry`, realimentação do histórico com mensagens `role: 'tool'` e parada por resposta sem ferramentas ou por `maxToolRounds`.

---

### Cliente Ollama
**Arquivo a criar:** `docs/flow/cliente-ollama.md`
**Resumo:** Montagem e envio do POST `/api/chat` (`stream: false`, `temperature: 0.1`, ferramentas serializadas por `ToolDefinition.toJson`), tratamento de status HTTP e conversão do corpo em `AgentMessage` com `InferenceMetrics`.

---

### Descoberta do Ollama
**Arquivo a criar:** `docs/flow/descoberta-do-ollama.md`
**Resumo:** Verificação do binário via `ollama --help`, listagem de modelos com `ollama list` e parsing da saída em `parseModelList` — usado apenas pela CLI; o app desktop resolve por HTTP.

---

### Ferramentas de workspace
**Arquivo a criar:** `docs/flow/ferramentas-de-workspace.md`
**Resumo:** Do despacho da `ToolCall` no `ToolRegistry` até o resultado em texto de `read_file`, `write_file`, `replace_in_file` e `run_command`, incluindo a resolução de caminho com symlinks em `WorkspaceTool.resolveFile`, os limites de truncamento e o mapeamento de exceções para strings `ERRO:`.

---

### Menções de arquivo (`@`)
**Arquivo a criar:** `docs/flow/mencoes-de-arquivo.md`
**Resumo:** Indexação de arquivos do projeto com diretórios ignorados, detecção da menção ativa sob o cursor, ranqueamento das sugestões e expansão do prompt com o conteúdo dos arquivos citados, com os avisos de arquivo inexistente, binário, não-UTF-8 ou acima de 512 KiB.

---

### Editor de linha do terminal
**Arquivo a criar:** `docs/flow/editor-de-linha-do-terminal.md`
**Resumo:** Ciclo de `TerminalInput.readLine`: entrada em modo raw, leitura caractere a caractere, teclas de escape e setas, renderização do menu de autocomplete de `@arquivo` e comandos `/`, completar com `Tab` e restauração do terminal no encerramento.

---

### Configuração e inicialização da CLI
**Arquivo a criar:** `docs/flow/inicializacao-da-cli.md`
**Resumo:** De `main(arguments)` até o chat ativo: parsing em `CliConfig.parse` com flags e variáveis de ambiente, validação do Ollama, seleção interativa do modelo, tratamento dos comandos `/clear`, `/exit` e `/quit` e os códigos de saída `64` e `69`.

---

## Já documentados

- `docs/flow/project-structure.md` — Estrutura geral do projeto
- `docs/flow/app-desktop.md` — App desktop: bootstrap do `AppInjector`, `WorkspaceCubit`/`ChatCubit`/`FileExplorerCubit`/`SettingsCubit`, conexão HTTP com o Ollama, configurações, atividade/sessões e árvore/preview no `DesktopView`
