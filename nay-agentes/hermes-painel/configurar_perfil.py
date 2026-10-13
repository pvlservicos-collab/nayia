# -*- coding: utf-8 -*-
"""Ajusta o config.yaml de um perfil do Hermes criado para o painel. Uso: python configurar_perfil.py <pasta do perfil>
Roda com o Python do Hermes (tem o PyYAML), pelo instalar.sh, toda vez que ele roda: o que está aqui é o que vale.

- modelo: gpt-5.6-luna direto na OpenAI (o mesmo que os outros perfis usavam);
- ferramentas: SÓ navegador, visão, memória, skills, lista de passos e busca em conversas. Sem terminal, sem arquivo,
  sem rodar código, sem subagente: o agente lê páginas e conversas escritas por estranhos, e o que ele lê não pode
  virar comando no servidor. Vale para a conversa do painel (api_server) e para as tarefas agendadas (cron).
"""
import pathlib
import sys

import yaml

pasta = pathlib.Path(sys.argv[1])
arq = pasta / "config.yaml"
conf = (yaml.safe_load(arq.read_text(encoding="utf-8")) if arq.exists() else None) or {}
conf["model"] = {"default": "gpt-5.6-luna", "provider": "custom", "base_url": "https://api.openai.com/v1"}
conf["timezone"] = "America/Manaus"
ferramentas = ["browser", "vision", "memory", "skills", "todo", "session_search"]
por_plataforma = conf.get("platform_toolsets") if isinstance(conf.get("platform_toolsets"), dict) else {}
por_plataforma["api_server"] = ferramentas
por_plataforma["cron"] = ferramentas
conf["platform_toolsets"] = por_plataforma
arq.write_text(yaml.safe_dump(conf, allow_unicode=True, sort_keys=False), encoding="utf-8")
print("config do perfil %s: modelo %s, ferramentas %s" % (pasta.name, conf["model"]["default"], ", ".join(ferramentas)))
