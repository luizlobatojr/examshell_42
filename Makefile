.PHONY: all run help check

SCRIPT := ./examshell.sh
ARGS ?=

all: run

run:
	@$(SCRIPT) $(ARGS)

check:
	bash -n $(SCRIPT)

help:
	@echo "Uso: make [run] [ARGS='-e exam-01 -t 60']"
	@echo "      make check"
	@echo "      make help"
