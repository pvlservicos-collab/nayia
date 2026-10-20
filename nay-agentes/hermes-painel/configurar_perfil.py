# -*- coding: utf-8 -*-
"""Ajusta o config.yaml de um perfil do Hermes criado para o painel. Uso: python configurar_perfil.py <pasta do perfil>
Roda com o Python do Hermes (tem o PyYAML), pelo instalar.sh (olx) e pelo instalar-claude.sh (claude), toda vez que
eles rodam: o que está aqui é o que vale.

- modelo: gpt-5.6-luna direto na OpenAI (o mesmo que os outros perfis usavam);
- olx: SÓ navegador, visão, memória, skills, lista de passos e busca em conversas. Sem terminal, sem arquivo,
  sem rodar código, sem subagente: o agente lê páginas e conversas escritas por estranhos, e o que ele lê não pode
  virar comando no servidor. Vale para a conversa do painel (api_server) e para as tarefas agendadas (cron).
- claude (Pedro, 20/10/2026: "outro hermes só para isso fora da olx, esse hermes só vai falar comigo"): memória,
  lista de passos, agenda (cronjob), busca em conversas e a ferramenta `agente` (mcp_agente.py: listar e disparar as
  regras do painel agentes.imobeasy.online). Sem terminal: quem mexe nos servidores é o Claude, pela regra.
  Fuso de Brasília, o do Pedro.
"""
import pathlib
import sys

import yaml

PERFIS = {
    "olx": {"ferramentas": ["browser", "vision", "memory", "skills", "todo", "session_search"],
            "fuso": "America/Manaus"},
    "claude": {"ferramentas": ["memory", "todo", "cronjob", "session_search", "agente"],
               "fuso": "America/Sao_Paulo",
               "mcp": {"agente": {"command": "/usr/local/lib/hermes-agent/venv/bin/python",
                                  "args": ["/opt/agente-claude/mcp_agente.py"],
                                  "timeout": 3600}}},
}

pasta = pathlib.Path(sys.argv[1])
perfil = PERFIS[pasta.name]
arq = pasta / "config.yaml"
conf = (yaml.safe_load(arq.read_text(encoding="utf-8")) if arq.exists() else None) or {}
conf["model"] = {"default": "gpt-5.6-luna", "provider": "custom", "base_url": "https://api.openai.com/v1"}
conf["timezone"] = perfil["fuso"]
ferramentas = perfil["ferramentas"]
por_plataforma = conf.get("platform_toolsets") if isinstance(conf.get("platform_toolsets"), dict) else {}
por_plataforma["api_server"] = ferramentas
por_plataforma["cron"] = ferramentas
conf["platform_toolsets"] = por_plataforma
if perfil.get("mcp"):
    conf["mcp_servers"] = perfil["mcp"]
arq.write_text(yaml.safe_dump(conf, allow_unicode=True, sort_keys=False), encoding="utf-8")
print("config do perfil %s: modelo %s, ferramentas %s" % (pasta.name, conf["model"]["default"], ", ".join(ferramentas)))
