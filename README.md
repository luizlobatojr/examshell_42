# Exam Shell 42 🚀

Uma interface de terminal interativa desenvolvida para treinar e simular exames da 42 por exercício e nível, permitindo aprimorar lógica, gerenciamento de tempo e rigor técnico em C.

---

## 📋 Sumário
* [Visão Geraal](#-visão-geral)
* [Requisitos do Sistema](#-requisitos-do-sistema)
* [Como Executar (Makefile)](#-como-executar-makefile)
* [Opções de Linha de Comando](#-opções-de-linha-de-comando)
* [Atalhos do Makefile](#-atalhos-do-makefile)
* [Comandos Durante o Exercício](#-comandos-durante-o-exercício)
* [Licença](#-licença)

---

## 🔍 Visão Geral

O programa apresenta enunciados, permite editar ou carregar soluções em C, compila o código com avisos estritos, verifica funções permitidas e executa testes automatizados sempre que disponíveis.

> **Nota importante:** Os testes automatizados funcionam como verificações parciais para auxiliar no treino diário e **não substituem** a correção oficial da 42.

---

## ⚙️ Requisitos

Certifique-se de que o seu ambiente possui os seguintes utilitários e dependências:
* **Bash** (versão 4 ou superior)
* **Python 3**
* **Compilador C** (`cc` ou `gcc`)
* **Utilitários Unix essenciais:** `nm`, `timeout`, `awk`, `sort`, `find`, `sed`, `grep`, `tr`, `xargs`, `basename`, `mkdir`, `cp`, `cat`, `date`, `git`

---

## 🚀 Como Executar (Makefile)

O projeto foi estruturado para ser executado de forma prática através do Makefile na pasta raiz:

```bash
make
