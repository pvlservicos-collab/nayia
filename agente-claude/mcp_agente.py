"""A ferramenta do Hermes do Claude (perfil `claude`): listar as regras do painel e disparar uma delas.

Pedro, 20/10/2026: o Hermes manda ao Claude, na hora que ele marcar, as ordens escritas no painel
agentes.imobeasy.online. O Hermes NÃO tem terminal: só estas duas ferramentas. Quem mexe no servidor é o Claude.
Roda com o Python do Hermes (tem o pacote mcp), lançado pelo próprio Hermes (mcp_servers.agente do config.yaml).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agente  # noqa: E402
from mcp.server.fastmcp import FastMCP  # noqa: E402

mcp = FastMCP("agente")


@mcp.tool()
def listar_regras() -> str:
    """Lista as regras (ordens) do painel: nome, se está ativa, servidor, modo e a mensagem que vai ao Claude."""
    linhas = []
    for nome, r in agente.regras().items():
        r = {**agente.PADRAO, **r}
        linhas.append(f"- {nome}: {'ativa' if r['ativa'] else 'PARADA'}, servidor {r['servidor']}, modo {r['modo']}"
                      f"\n  mensagem: {r['mensagem']}")
    return "\n".join(linhas) or "Nenhuma regra no painel."


@mcp.tool()
def disparar_regra(nome: str) -> str:
    """Manda ao Claude a mensagem da regra `nome`, exatamente como está no painel, e devolve o resultado.
    Modo "alterar": o Claude mexe no servidor como root; pode levar até 30 minutos."""
    try:
        linhas = agente.executar([nome], origem="hermes")
    except KeyError as e:
        return e.args[0] + ". Use listar_regras para ver os nomes."
    if not linhas:
        return f"A regra {nome} está parada no painel; nada foi mandado."
    l = linhas[0]
    tempo = f"{(l.get('ms_total') or 0) / 1000:.1f} s"
    if l["ok"]:
        return f"OK em {tempo} (servidor {l['servidor']}, modo {l['modo']}). Resposta do Claude:\n{l.get('resposta') or ''}"
    return f"ERRO em {tempo} (servidor {l['servidor']}): {l.get('erro') or ''}"


if __name__ == "__main__":
    mcp.run()
