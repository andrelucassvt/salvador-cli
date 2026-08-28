# Leve CLI

Agente de codigo em Dart, leve e 100% local, criado para modelos pequenos
servidos pelo Ollama.

## Estado atual

O primeiro fluxo vertical esta implementado: na inicializacao, o CLI verifica
se o Ollama esta instalado, executa `ollama list` e permite selecionar um dos
modelos encontrados. Depois, conversa com `/api/chat`, oferece ferramentas ao
modelo e devolve os resultados ate ele produzir a resposta final. As
ferramentas de arquivo ficam limitadas a raiz escolhida:

- `read_file`: le texto;
- `write_file`: cria ou sobrescreve texto;
- `replace_in_file`: faz uma substituicao exata e unica;
- `run_command`: executa um comando, iniciado na raiz, com timeout de 30 segundos.

> `run_command` nao e um sandbox: o processo conserva as permissoes do usuario.

## Executar

Requer Dart 3.12+ e um Ollama ativo com um modelo que suporte tool calling.

```sh
ollama pull qwen2.5-coder:3b
dart pub get
dart run bin/salvador_cli.dart
```

Opcoes:

```text
--model NOME     Pula a selecao interativa (ou OLLAMA_MODEL)
--host URL       Servidor (ou OLLAMA_HOST)
--root CAMINHO   Raiz acessivel ao agente
```

No chat, `/clear` limpa o historico e `/exit` encerra o programa.

## Validar

```sh
dart analyze
dart test
```
