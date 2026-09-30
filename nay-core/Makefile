# nay-core: um comando para cada coisa. Ver CLAUDE.md.
# No servidor, a pasta é $(SERVIDOR_DIR) e o container é nay-core.
PY ?= python
SERVIDOR_DIR ?= /opt/nayia/nay-core

.PHONY: test lint limites migrar migrar-ensaio deploy rollback replay comparar violacoes

test:            ## a suíte inteira, sem rede, em menos de 60 s
	$(PY) -m pytest

lint:            ## estilo, complexidade e os limites de tamanho do projeto
	$(PY) -m ruff check nay tests scripts
	$(PY) scripts/limites.py

migrar-ensaio:   ## aplica as migrações pendentes numa transação e desfaz
	$(PY) scripts/migrar.py --ensaio

migrar:          ## aplica as migrações pendentes (tabela core_migracao)
	$(PY) scripts/migrar.py

deploy:          ## no servidor: git pull, testes, migração, sobe o container, healthcheck
	cd $(SERVIDOR_DIR) && git pull --ff-only
	cd $(SERVIDOR_DIR) && docker compose run --rm --no-deps nay-core make test
	cd $(SERVIDOR_DIR) && docker compose run --rm --no-deps nay-core python scripts/migrar.py
	cd $(SERVIDOR_DIR) && git rev-parse HEAD > .ultimo_deploy && docker compose up -d --build nay-core
	$(PY) scripts/esperar_saude.py

rollback:        ## volta ao commit anterior ao último deploy e sobe de novo (migração não volta)
	cd $(SERVIDOR_DIR) && git checkout HEAD~1 && docker compose up -d --build nay-core
	$(PY) scripts/esperar_saude.py

replay:          ## reprocessa os turnos reais dos últimos 30 dias em modo teste
	$(PY) scripts/replay.py --dias 30

comparar:        ## relatório do dia: sombra (nay-core) x Nay atual
	$(PY) scripts/comparar.py --dia hoje

violacoes:       ## transforma as paredes que agiram em 30 dias em casos YAML
	$(PY) scripts/exportar_violacoes.py --dias 30
