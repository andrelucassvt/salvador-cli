# Redesenho Desktop do Salvador — Parte 2: Estado persistente

> **Objetivo da parte:** restaurar e salvar preferências, pastas recentes e resumos de sessões, expondo no `DesktopController` o estado necessário para os novos controles.
> **Plano:** `00-indice.md` (Design de Origem, ordem e dependências)
> **Depende de:** parte 1 concluída

## Contexto

O controlador atual mantém tudo em memória, mistura validação da conexão com reconstrução da sessão e não recebe dependências suficientes para testar modelos reais sem processo/rede. Esta parte cria o armazenamento do app e reorganiza o estado sem ainda substituir a interface visual.

## Arquitetura / Escopo

| Arquivo | Ação | Responsabilidade |
|---------|------|-----------------|
| `app/lib/src/desktop/desktop_state_store.dart` | criar | Schema JSON versionado, caminho por sistema operacional e gravação atômica |
| `app/lib/src/desktop/system_memory.dart` | criar | RAM disponível por macOS/Linux/Windows com runner injetável |
| `app/lib/src/desktop/desktop_controller.dart` | alterar | Estado da top bar, configurações, sessões, recentes, modelos e ações assíncronas |
| `app/test/desktop_state_store_test.dart` | criar | Round-trip, defaults, corrupção e limites do armazenamento |
| `app/test/system_memory_test.dart` | criar | Parsing das fontes de memória por plataforma |
| `app/test/desktop_controller_test.dart` | alterar | Restauração, troca de pasta/modelo, sessões e conexão sem rede/processo real |

## Fases

### Fase 1 — Testes do armazenamento

> Os testes vão falhar inicialmente — isso é intencional.

- [x] Criar `app/test/desktop_state_store_test.dart` com diretório temporário injetado e round-trip de host, modelo, parâmetros, permissões e pasta ativa.
- [x] Testar em `app/test/desktop_state_store_test.dart` ordenação/deduplicação das pastas recentes e retenção limitada dos resumos de sessão.
- [x] Testar em `app/test/desktop_state_store_test.dart` fallback para defaults em arquivo inexistente, JSON corrompido, versão desconhecida e campos opcionais ausentes.
- [x] Testar em `app/test/desktop_state_store_test.dart` que a gravação substitui o arquivo final sem deixar um JSON parcialmente escrito.
- [x] Verificação: `cd app && flutter test test/desktop_state_store_test.dart` compila e falha pela ausência do store.

### Fase 2 — Implementação do armazenamento

- [x] Criar em `app/lib/src/desktop/desktop_state_store.dart` `DesktopPersistedState`, `PersistedSessionSummary` e serialização JSON versionada.
- [x] Resolver em `DesktopStateStore.defaultFile` os diretórios `Application Support` no macOS, `APPDATA` no Windows e `XDG_CONFIG_HOME`/`.config` no Linux, permitindo `File` injetável em testes.
- [x] Implementar em `DesktopStateStore` leitura defensiva e gravação atômica por arquivo temporário no mesmo diretório seguida de rename.
- [x] Limitar no store as coleções persistidas a uma quantidade explícita de recentes e resumos, preservando os itens mais novos.
- [x] Verificação: `cd app && flutter test test/desktop_state_store_test.dart` passa.

### Fase 3 — Testes de memória e controlador

> Os testes vão falhar inicialmente — isso é intencional.

- [x] Criar `app/test/system_memory_test.dart` para saídas representativas de `vm_stat`/`sysctl` no macOS, `/proc/meminfo` no Linux e PowerShell/CIM no Windows, incluindo resultado indisponível.
- [x] Ampliar `app/test/desktop_controller_test.dart` com factory de cliente injetada para inicialização restaurada sem Ollama real.
- [x] Testar em `app/test/desktop_controller_test.dart` a troca de modelo: salvar seleção, reconstruir sessão, carregar o novo modelo e atualizar o estado vindo de `/api/ps`.
- [x] Testar em `app/test/desktop_controller_test.dart` iniciar/encerrar modelo, testar servidor, salvar parâmetros/permissões e propagar erros sem descartar o último estado válido.
- [x] Testar em `app/test/desktop_controller_test.dart` que servidor conectado e modelo carregado são estados separados: com modelo parado, configuração continua disponível e envio pede para iniciar o modelo.
- [x] Testar em `app/test/desktop_controller_test.dart` troca de pasta, recentes deduplicadas e criação persistida de resumo ao iniciar nova sessão.
- [x] Verificação: `cd app && flutter test test/system_memory_test.dart test/desktop_controller_test.dart` compila e falha somente pelos contratos ausentes.

### Fase 4 — Implementação do estado desktop

- [x] Criar `SystemMemoryReader` em `app/lib/src/desktop/system_memory.dart` com fontes específicas por plataforma, runner injetável e retorno anulável quando a métrica não puder ser obtida.
- [x] Refatorar `DesktopController` em `app/lib/src/desktop/desktop_controller.dart` para aceitar `DesktopStateStore`, factory de cliente Ollama, leitor de memória e relógio injetáveis.
- [x] Fazer `DesktopController.initialize` restaurar o JSON, validar a raiz e consultar o servidor por `/api/tags` e `/api/ps`, mantendo `OllamaDiscovery` e o runner de caminhos absolutos somente onde a CLI/compatibilidade existente ainda exigir.
- [x] Separar no controlador o estado da conexão HTTP do estado carregado/parado do modelo selecionado, desabilitando envio quando o modelo estiver parado sem impedir acesso às configurações.
- [x] Implementar no controlador `selectRoot`, `selectModel`, `startModel`, `stopModel`, `testHost`, `saveSettings` e `newSession`, persistindo apenas após sucesso quando a ação puder falhar.
- [x] Construir resumos de sessão pelo primeiro prompt não vazio, data e número de atividades, sem serializar mensagens nem restaurá-las no `AgentSession`.
- [x] Verificação: `cd app && flutter test test/system_memory_test.dart test/desktop_controller_test.dart` passa.

### Fase 5 — Integridade da parte

- [x] Rodar `dart format app/lib/src/desktop/desktop_state_store.dart app/lib/src/desktop/system_memory.dart app/lib/src/desktop/desktop_controller.dart app/test/desktop_state_store_test.dart app/test/system_memory_test.dart app/test/desktop_controller_test.dart`.
- [x] Rodar `cd app && flutter analyze && flutter test`.
- [x] Rodar `dart analyze && dart test` na raiz para confirmar que a refatoração desktop não alterou o pacote/CLI indevidamente.
- [x] Checkpoint: commit das mudanças da parte + resumo curto do que ficou pronto, seguindo direto para a parte 3.

## Critérios de Sucesso

- [x] Preferências, recentes e resumos de sessões sobrevivem a uma nova instância do controlador.
- [x] JSON inválido não impede a inicialização e não apaga silenciosamente o último arquivo até um novo save válido.
- [x] O controlador representa modelos instalados/ativos e executa carga, descarga e teste de conexão por dependências testáveis.
- [x] Todos os testes automatizados e análises estáticas passam.

> **Nota de execução:** o controlador desktop deixou de invocar o binário `ollama` — descoberta e listagem passaram a ser HTTP (`/api/tags`, `/api/ps`), então `OllamaDiscovery` e o runner de caminhos absolutos saíram do `desktop_controller.dart`. A CLI de `bin/` continua usando `OllamaDiscovery` sem alteração.

## Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Paths de configuração variarem em ambientes sem variáveis padrão | Média | Fallback explícito para diretório suportado e erro apresentável, com path injetável nos testes |
| Inicialização emitir estados em ordem instável | Média | Testes de transição e métodos assíncronos serializados no controlador |
| Resumo de sessão gravar conteúdo excessivo | Baixa | Título truncado e somente metadados aprovados, sem conteúdo da conversa |

## Rollback

Reverter o commit da parte remove o store e volta ao estado em memória. O JSON eventualmente criado permanece inerte e pode ser reutilizado numa nova tentativa.
