# Redesenho Desktop do Salvador — Parte 1: Ollama e permissões

> **Objetivo da parte:** disponibilizar contratos testados para metadados e estado real dos modelos, carga/descarga, parâmetros de inferência e filtragem das ferramentas permitidas.
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** nenhuma

## Contexto

`OllamaClient` hoje implementa apenas `/api/chat`, com temperatura fixa, enquanto `OllamaDiscovery` retorna somente nomes extraídos de `ollama list`. `AgentSession` sempre cria as quatro ferramentas, então o desktop ainda não consegue cumprir os controles e permissões descritos no redesign.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `lib/src/models.dart` | alterar | Modelos imutáveis para parâmetros de inferência e metadados/estado do Ollama |
| `lib/src/ollama_client.dart` | alterar | `/api/tags`, `/api/ps`, `/api/show`, teste de conexão, preload/unload e chat configurável |
| `lib/src/tools.dart` | alterar | `AgentPermissions` e filtragem das definições/execuções de edição e comando |
| `lib/src/agent.dart` | alterar | Receber permissões e observar conclusão das ferramentas sem quebrar `onToolCall` |
| `test/ollama_client_test.dart` | alterar | Contratos HTTP e parsing dos novos endpoints e parâmetros |
| `test/salvador_cli_test.dart` | alterar | Contrato de permissões e atividade concluída no loop do agente |

## Fases

### Fase 1 — Testes do contrato Ollama

> Os testes vão falhar inicialmente — isso é intencional.

- [ ] Ampliar `test/ollama_client_test.dart` com `HttpServer` local para verificar parsing de nome, tamanho, família, quantização e data retornados por `/api/tags`.
- [ ] Testar em `test/ollama_client_test.dart` a combinação de `/api/ps` com os modelos instalados, incluindo `size_vram`, `context_length`, expiração e campos ausentes.
- [ ] Testar em `test/ollama_client_test.dart` `/api/show` para recuperar o contexto de um modelo parado sem tornar o campo obrigatório.
- [ ] Testar em `test/ollama_client_test.dart` preload e unload via `/api/generate`, exigindo `stream: false`, prompt vazio e `keep_alive` correto.
- [ ] Testar em `test/ollama_client_test.dart` que `/api/chat` envia temperatura, `num_ctx` e `keep_alive`, e transforma timeout/status inválido em `OllamaException`.
- [ ] Verificação: `dart test test/ollama_client_test.dart` compila e falha somente pela ausência dos novos contratos.

### Fase 2 — Implementação do runtime Ollama

- [ ] Criar em `lib/src/models.dart` os tipos `OllamaModelInfo`, `OllamaRunningModel` e `InferenceOptions`, com parsing tolerante e valores padrão para metadados opcionais.
- [ ] Ampliar `OllamaClient` em `lib/src/ollama_client.dart` com `testConnection`, `listModels`, `listRunningModels`, `showModel`, `loadModel` e `unloadModel`, reutilizando `HttpClient` injetável.
- [ ] Alterar `OllamaClient.chat` em `lib/src/ollama_client.dart` para aplicar `InferenceOptions` sem mudar `stream: false` nem o parsing atual de métricas/tool calls.
- [ ] Centralizar em `lib/src/ollama_client.dart` leitura de JSON, validação de status e timeout para que todos os endpoints gerem mensagens `OllamaException` consistentes.
- [ ] Manter `OllamaDiscovery` responsável pela presença do binário e compatibilidade da CLI, sem mover Flutter ou dependências externas para `lib/`.
- [ ] Verificação: `dart test test/ollama_client_test.dart` passa e `dart analyze` não apresenta erros.

### Fase 3 — Testes das permissões e da atividade

> Os testes vão falhar inicialmente — isso é intencional.

- [ ] Adicionar em `test/salvador_cli_test.dart` casos que comprovem que leitura sempre permanece disponível, edição remove `write_file`/`replace_in_file` e comando remove `run_command` das definições enviadas ao modelo.
- [ ] Testar em `test/salvador_cli_test.dart` que uma chamada forjada para ferramenta desabilitada retorna `ERRO: ferramenta nao permitida` e não toca o filesystem/processo.
- [ ] Testar em `test/salvador_cli_test.dart` que o novo observador de conclusão recebe `ToolCall` e resultado depois da execução, preservando o observador `onToolCall` existente.
- [ ] Verificação: `dart test test/salvador_cli_test.dart` compila e falha somente pelos novos contratos ainda ausentes.

### Fase 4 — Implementação das permissões

- [ ] Criar `AgentPermissions` em `lib/src/tools.dart`, com edição e comandos configuráveis, leitura sempre habilitada e constante `readOnly` para consumidores que só podem ler.
- [ ] Alterar `ToolRegistry` em `lib/src/tools.dart` para construir somente as ferramentas permitidas e rejeitar explicitamente execuções que não estejam no registro.
- [ ] Alterar `AgentSession` em `lib/src/agent.dart` para receber `AgentPermissions` e um `ToolResultObserver`, preservando defaults e compatibilidade da CLI.
- [ ] Fazer `AgentSession.sendDetailed` notificar conclusão somente depois de obter o resultado textual da ferramenta, inclusive resultados `ERRO:`.
- [ ] Verificação: `dart test test/salvador_cli_test.dart` e `dart test` passam.

### Fase 5 — Integridade da parte

- [ ] Rodar `dart format lib/src/models.dart lib/src/ollama_client.dart lib/src/tools.dart lib/src/agent.dart test/ollama_client_test.dart test/salvador_cli_test.dart`.
- [ ] Rodar `dart analyze` e `dart test` a partir da raiz.
- [ ] Rodar `cd app && flutter analyze && flutter test` para confirmar compatibilidade dos contratos públicos com o frontend existente.
- [ ] Checkpoint: commit das mudanças da parte + resumo curto do que ficou pronto, seguindo direto para a parte 2.

## Critérios de Sucesso

- [ ] Modelos instalados e carregados são representados por dados tipados e testados.
- [ ] O cliente carrega/descarrega modelos e aplica contexto, temperatura, timeout e keep-alive.
- [ ] Edição e execução de comandos podem ser removidas das ferramentas expostas ao modelo.
- [ ] `dart analyze`, `dart test`, `flutter analyze` e `flutter test` passam.

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Extender `OllamaClient` quebrar os testes ou a CLI existentes | Média | Preservar construtor e defaults atuais; adicionar APIs sem mudar `ChatClient` além do necessário |
| Tool call não permitida escapar por resposta direta do modelo | Baixa | Validar também na execução do `ToolRegistry`, não apenas na lista de definições |

## Rollback

Reverter o commit desta parte restaura os contratos anteriores sem tocar em dados persistidos ou arquivos do usuário.
