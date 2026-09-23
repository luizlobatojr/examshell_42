# Exam Shell 42

Uma interface de terminal para praticar exames da 42 por exercício e nível. O programa apresenta os enunciados, permite editar ou carregar soluções em C, compila com avisos estritos, verifica funções permitidas e executa testes automáticos quando há casos de teste ou um teste de função disponível.

Os testes automáticos são verificações parciais para ajudar no treino; não substituem a correção oficial da 42.

## Requisitos

- Bash 4 ou superior
- Python 3
- Um compilador C, como `cc` ou `gcc`
- Utilitários Unix: `nm`, `timeout`, `awk`, `sort`, `find`, `sed`, `grep`, `tr`, `xargs`, `basename`, `mkdir`, `cp`, `cat` e `date`

## Iniciar

Na pasta do projeto:

```sh
./examshell.sh
```

O menu inicial permite escolher um exame, iniciar o Modo Real, sortear um exame ou sair com `q`. Também é possível iniciar um exame diretamente:

```sh
./examshell.sh -e exam-00
./examshell.sh -e final-exam -t 180
./examshell.sh -e real
./examshell.sh -t 0
```

A duração é informada em minutos; `-t 0` remove o limite de tempo. Para usar um banco de exercícios noutra pasta:

```sh
./examshell.sh -d /caminho/para/exam-practice -e exam-00
```

Use `./examshell.sh -h` para ver as opções. O Makefile também oferece atalhos:

```sh
make
make run ARGS='-e exam-01 -t 60'
make check
make help
```

## Durante o exercício

- `e`: editar o ficheiro esperado no editor configurado em `$EDITOR` (ou `vi`)
- `l`: carregar um ficheiro existente
- `c`: compilar e executar as verificações disponíveis
- `t`: repetir os testes automáticos
- `r`: executar manualmente o programa compilado
- `s`: mostrar novamente o enunciado
- `n`: avançar quando a compilação e as verificações passam
- `k`: saltar o exercício
- `q`: terminar a sessão

Os ficheiros de trabalho e registos das sessões são guardados em `~/.examshell/sessions/`.

## Banco de exercícios

Por padrão, o programa procura `exam-practice/` junto de `examshell.sh`. O banco incluído contém enunciados associados ao projeto [42porto-piscine-17](https://github.com/GTitonele/42porto-piscine-17). Os enunciados e materiais de terceiros podem ter termos de licença próprios; consulte a origem antes de os redistribuir.

## Licença

O código deste projeto está disponível sob a licença MIT; consulte [LICENSE](LICENSE). Essa licença não altera os termos aplicáveis ao banco de exercícios ou a outros materiais de terceiros.
