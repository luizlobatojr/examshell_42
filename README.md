# Exam Shell 42

Aplicação de terminal para praticar exames da 42 em C. O Exam Shell apresenta os enunciados por nível, permite editar e compilar soluções, verifica funções permitidas e executa testes automáticos quando existem.

Os testes são auxiliares e parciais; não substituem a avaliação oficial da 42.

## Requisitos

- Bash 4 ou superior
- Python 3
- Compilador C disponível como `cc` ou `gcc`
- Utilitários: `nm`, `timeout`, `awk`, `sort`, `find`, `sed`, `grep`, `tr`, `xargs`, `basename`, `mkdir`, `cp`, `cat` e `date`
- `git` e `mktemp` para atualizar o projeto ou o banco de exercícios

Ao iniciar, o programa verifica as dependências e a estrutura do banco. A ausência de dependências essenciais ou de um banco utilizável impede o início; problemas pontuais nos enunciados são apresentados como avisos.

## Início rápido

Na pasta do projeto, execute:

```sh
./examshell.sh
```

Ou use o Makefile:

```sh
make
```

O menu permite escolher um exame, iniciar o Modo Real, sortear um exame, selecionar manualmente um nível e exercício, atualizar o projeto ou atualizar apenas o banco de exercícios.

## Linha de comando

```text
./examshell.sh [-d PASTA_DO_BANCO] [-e EXAME] [-t MINUTOS] [-h]
```

| Opção | Descrição |
| --- | --- |
| `-d CAMINHO` | Usa um banco de exercícios noutra pasta. Por padrão, usa `exam-practice/` junto do script. |
| `-e EXAME` | Inicia diretamente `exam-00`, `exam-01`, `exam-02`, `final-exam`, `real` ou `random`. |
| `-t MINUTOS` | Define a duração total da sessão. Use `0` para não impor limite. |
| `-h` | Mostra a ajuda. |

Exemplos:

```sh
./examshell.sh -e exam-00
./examshell.sh -e final-exam -t 180
./examshell.sh -e real
./examshell.sh -e random -t 45
./examshell.sh -d ~/repos/42porto-piscine-17/exam-practice -e random
```

Sem `-e`, o menu inicial solicita uma escolha. As durações padrão são 60 minutos para exames regulares, 180 minutos para `final-exam` e sem limite para o Modo Real. `-t` substitui o padrão.

## Menu inicial

- **Número:** inicia o exame correspondente. O programa sorteia um exercício por nível.
- **`m`:** inicia o Modo Real, percorrendo `exam-00`, `exam-01`, `exam-02` e `final-exam`.
- **`r`:** sorteia um exame.
- **`s`:** permite escolher o exame, o nível e um exercício específico. Na lista de exercícios, `r` sorteia um exercício dentro do nível selecionado.
- **`u`:** sincroniza o projeto com o GitHub por fast-forward. Se houver conflitos ou a atualização falhar, o Git interrompe a operação e o programa apresenta uma mensagem. Depois de uma sincronização bem-sucedida, reinicie o programa.
- **`b`:** atualiza somente a pasta `exam-practice/` a partir do repositório de exercícios [42porto-piscine-17](https://github.com/GTitonele/42porto-piscine-17/tree/main/exam-practice). Esta opção está disponível para o banco incluído no projeto e requer que ele não tenha alterações locais. O código do Exam Shell não é atualizado por essa ação.
- **`q`:** sai do programa.

O estado de atualização do projeto é consultado ao abrir o menu. Essa consulta requer ligação ao GitHub; se não estiver disponível, a opção de atualização continua acessível.

## Durante o exercício

O cronómetro mostra o tempo restante e atualiza a cada segundo enquanto aguarda comandos num terminal interativo. Quando restam cinco minutos ou menos, apresenta um aviso. O contador é global para a sessão.

| Tecla | Ação |
| --- | --- |
| `e` | Edita o ficheiro esperado com o programa definido em `$EDITOR` (ou `vi`). |
| `l` | Carrega um ficheiro existente para a pasta de trabalho. |
| `c` | Compila com `-Wall -Wextra -Werror -Wpedantic`, verifica as funções permitidas e executa os testes disponíveis. |
| `t` | Repete os testes automáticos da última compilação. |
| `r` | Executa o programa compilado e permite informar argumentos. |
| `s` | Mostra novamente o enunciado. |
| `n` | Avança quando a compilação e os testes passam; se falharem, permite confirmar o avanço. |
| `k` | Salta o exercício. |
| `q` | Termina a sessão. |

Ao terminar, o relatório lista os exercícios concluídos, saltados e pendentes, além do total de níveis. Sessões e registos são guardados em `~/.examshell/sessions/`.

## Banco de exercícios

Por padrão, os enunciados são lidos de `exam-practice/`, organizado por exame e por pastas `Level *`. O banco incluído contém materiais associados ao projeto [42porto-piscine-17](https://github.com/GTitonele/42porto-piscine-17). Os enunciados e materiais de terceiros podem ter termos de licença próprios; consulte a origem antes de os redistribuir.

As soluções criadas durante a prática ficam na pasta da sessão do utilizador, não dentro do banco de enunciados.

## Makefile

```sh
make                         # inicia o programa
make run ARGS='-e exam-01 -t 60'
make check                   # verifica a sintaxe Bash
make help
```

## Licença

O código do Exam Shell está disponível sob a licença MIT; consulte [LICENSE](LICENSE). Essa licença não altera os termos aplicáveis ao banco de exercícios ou a outros materiais de terceiros.
