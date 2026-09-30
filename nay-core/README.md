# nay-core

O núcleo novo da Nay, que substitui aos poucos o atendimento em n8n + PL/pgSQL.
Nesta entrega ele roda em **sombra**: recebe cópia de cada mensagem, decide a
resposta que daria, grava tudo e compara com o que a Nay atual enviou.
**Não envia nada** (o banco nem aceita: `core_saida.estado` só pode ser
`simulado`).

Por que existe: a camada que corrige depois do modelo é a que mais produz
imóvel errado e dado errado; o n8n é o gargalo de tempo; não havia máquina de
estados; o git não era a produção (retrato completo em
`docs/ENTREVISTA-2026-09-29.md`, perguntas 6, 13, 41, 42 e 45).

## Rodar os testes (local, sem rede)
```
python -m venv .venv && . .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -e ".[dev]"
make test      # < 60 s, sem tocar produção
make lint      # ruff + limites (300 linhas por arquivo, 60 por função)
```

## Banco
Migrações em `migrations/NNN_nome.sql`, aplicadas por `scripts/migrar.py`
(tabela `core_migracao`, md5 de cada arquivo; arquivo aplicado não se edita).
```
DATABASE_URL_MIGRACAO=... make migrar-ensaio   # aplica numa transação e desfaz
DATABASE_URL_MIGRACAO=... make migrar          # aplica o que falta
```

## Deploy (no servidor)
```
make deploy     # git pull, testes, migração, sobe o container, espera healthy
make rollback   # volta ao commit anterior e sobe (migração NÃO volta)
```

## Sombra
`make comparar` gera o relatório do dia: turnos vistos, quantos o core
respondeu sem modelo, concordância de imóvel com a Nay atual, divergências com
os dois textos lado a lado e exceções. `make replay` reprocessa os turnos reais
dos últimos 30 dias em modo teste.

Mapa de "onde eu mudo X": `CLAUDE.md`. Onde paramos: `docs/PROGRESSO.md`.
