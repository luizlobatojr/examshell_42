#include <unistd.h>

int main(int argc, char **argv)
{
    int i = 0;

    // Verifica se foi passado exatamente um argumento
    if (argc == 2)
    {
        while (argv[1][i])
        {
            // Se encontrar o caractere 'a', imprime 'a' e uma nova linha
            if (argv[1][i] == 'a')
            {
                write(1, "a\n", 2);
                return (0);
            }
            i++;
        }
    }

    // Se o número de parâmetros for diferente de 1 ou se não encontrar 'a'
    write(1, "a\n", 2);
    return (0);
}
