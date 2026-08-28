# Leve CLI

> Um harness de agente de linha de comando, no estilo do opencode, otimizado para rodar bem contra LLMs locais pequenos.

## Problema
Ferramentas como o opencode usam system prompts pesados, pensados para modelos grandes de nuvem (GPT-4, Claude, etc). Quando você aponta essas ferramentas pra um LLM local de poucos bilhões de parâmetros, o prompt pesado consome contexto, confunde o modelo e derruba a qualidade das respostas e do tool-calling. Hoje quem quer usar agente de código com LLM local não tem uma opção pensada pra essa limitação.

## Usuários
Devs que rodam LLMs locais (via Ollama, llama.cpp, etc) e querem um agente de terminal para tarefas de código, sem depender de nuvem. Andre é o primeiro usuário, mas a ferramenta é pensada para ser usada por outros devs também.

## Escopo do MVP
- [x] Conectar e rodar inferência contra LLM local (Ollama)
- [x] Execução de tool calls (leitura/escrita/edição de arquivos, rodar comandos)
- [x] System prompt enxuto, dimensionado para modelos pequenos
- [x] Interface de linha de comando interativa (chat contínuo, `/clear` e `/exit`)

## Fora do escopo
- Suporte a LLM em nuvem (OpenAI, Anthropic, etc) — o foco é 100% local
- Telemetria, atualização automática ou qualquer dependência de rede

## Stack e arquitetura
CLI em Dart. Roda 100% local e offline — a única dependência externa é o runtime do LLM local (Ollama ou llama.cpp) rodando na máquina do usuário. Distribuição via GitHub (releases).

## Modelo de dados
- **Sessão de agente**: histórico de mensagens, estado da tarefa em andamento
- **Configuração**: qual runtime local usar (Ollama/llama.cpp), qual modelo, parâmetros de inferência
- **Tool call**: nome da ferramenta, argumentos, resultado

## Riscos
- Enxugar o system prompt sem perder a capacidade de tool-calling é o maior risco técnico — ainda não está claro o quanto dá pra cortar sem o modelo "perder a mão" nas chamadas de ferramenta.
- Modelos pequenos tendem a alucinar mais em tool-calling; pode ser necessário validação/retry mais agressivo do que ferramentas voltadas a modelos grandes.
- Variação de comportamento entre runtimes (Ollama vs llama.cpp) e entre modelos pode exigir prompts/formatos de tool-call diferentes por combinação.

## Suposições assumidas
- [ ] Compatibilidade inicial com Ollama e llama.cpp (não foi confirmado se ambos ou só um deles entra na v1)
- [ ] Interface interativa de terminal similar ao opencode (não foi detalhado o formato exato: chat contínuo, comandos slash, etc)
- [ ] "Rodar tudo que o exemplo do opencode faz" foi interpretado como: tool calls + edição de arquivos + execução de comandos — o escopo completo de funcionalidades do opencode não foi levantado a fundo
- [ ] Não foi definida a abordagem para o risco do system prompt (ponto 8) — fica em aberto para investigação técnica antes ou durante a primeira entrega

## Primeira entrega
Um CLI mínimo que conecta a um modelo local via Ollama, roda um loop de agente simples com um system prompt enxuto, e consegue fazer pelo menos uma tool call de edição de arquivo de ponta a ponta — provando que o prompt reduzido não quebra o tool-calling.
