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

No chat:

- digite `@` para buscar arquivos do projeto sem sair da linha atual;
- continue digitando para filtrar, use as setas para escolher e `Tab` para
  inserir o caminho;
- caminhos com espacos sao inseridos como `@"meu arquivo.txt"`;
- o conteudo dos arquivos mencionados e enviado ao modelo junto da mensagem;
- digite `/` para listar e filtrar os comandos, use as setas para escolher e
  `Tab` para completar;
- `/clear` limpa o historico e `/exit` encerra o programa.

Diretorios de dependencias e artefatos (`.git`, `.dart_tool`, `build` e
`node_modules`, entre outros) nao aparecem nas sugestoes. Um caminho ainda
pode ser mencionado diretamente, desde que seja um arquivo UTF-8 dentro da
raiz. Cada arquivo mencionado tem limite de 512 KiB.

Ao fim de cada resposta, o CLI mostra uma linha tecnica como esta:

```text
metricas> 34.8 tok/s | 87 tokens de saida | 512 tokens de entrada | 2.50s gerando | 2.81s total
```

Os valores usam diretamente `eval_count`, `eval_duration`,
`prompt_eval_count` e `total_duration` devolvidos pelo Ollama. Quando o agente
faz chamadas de ferramentas, as contagens e duracoes de todas as geracoes da
resposta sao somadas.

## Validar

```sh
dart analyze
dart test
```
