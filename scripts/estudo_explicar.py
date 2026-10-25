"""O PAINEL DE ESTUDOS, PASSO 2 (Pedro, 25/10/2026): a explicação de cada função, em português informal ("cada jargão técnico
vai ter um () explicando dentro do () o significado ... como para um jovem entender").

Roda no servidor com o modelo do nay-olx (olx/modelo.py, a Luna), sobre os estudo-<nay>.json do passo 1
(scripts/estudo_gerar.py). Só escreve o que falta (função nova ou código mudado) e grava de 40 em 40.

  cd /root/nay-olx && set -a && . ./.env && set +a && .venv/bin/python /tmp/estudo/estudo_explicar.py /tmp/estudo/*.json
"""
import json
import sys
import threading
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, "/root/nay-olx")
from olx import modelo  # noqa: E402

TAGS = ["usa o modelo (IA)", "lê o banco", "grava no banco", "manda mensagem", "regra fixa", "decide o caminho",
        "confere/barra", "monta texto", "calcula", "espera/tempo", "registra (rastro)", "ajuda pequena"]

PROMPT = f"""Você explica código da Imob Easy (imobiliária de Manaus) para o dono, que NÃO é programador: escreva como para um
jovem de 16 anos, em português do Brasil informal, curto e certo. Todo termo técnico que você usar vem seguido do
significado entre parênteses, ex.: "o webhook (o endereço que o WhatsApp chama quando chega mensagem)".
Você recebe UMA função (Python ou SQL) de uma das Nays (as assistentes de WhatsApp) e o contexto de onde ela mora.
Devolva SÓ este JSON:
{{"resumo": "uma frase: o que ela faz no atendimento",
  "explicacao": "2 a 4 frases informais: para que serve, quando é chamada e o que devolve",
  "passos": ["o que o código faz, na ordem, em até 6 passos curtos"],
  "jargoes": [{{"termo": "palavra técnica do código ou da explicação", "significado": "em palavras simples"}}],
  "tags": ["até 4 destas: {', '.join(TAGS)}"]}}
Até 8 jargões. Não invente o que o código não faz."""

trava = threading.Lock()


def explicar(nay: dict, fn: dict) -> dict:
    ctx = (f"NAY: {nay['nome']} ({nay['quem']}): {nay['descricao']}\nARQUIVO: {fn['arquivo']} (linha {fn['linha']})\n"
           f"FUNÇÃO: {fn['nome']}\nCHAMA: {', '.join(fn.get('chama', [])[:12]) or '-'}\n"
           f"É CHAMADA POR: {', '.join(fn.get('chamada_por', [])[:8]) or '-'}\n\nCÓDIGO:\n{fn['codigo'][:7000]}")
    try:
        r = modelo.chamar(PROMPT, ctx, no="olx.replay")
    except Exception as e:  # noqa: BLE001
        return {"falha": str(e)[:200]}
    return {"resumo": str(r.get("resumo") or "")[:300], "explicacao": str(r.get("explicacao") or "")[:1200],
            "passos": [str(p)[:240] for p in (r.get("passos") or [])][:6],
            "jargoes": [{"termo": str(j.get("termo") or "")[:60], "significado": str(j.get("significado") or "")[:220]}
                        for j in (r.get("jargoes") or []) if isinstance(j, dict) and j.get("termo")][:8],
            "tags": [t for t in (r.get("tags") or []) if t in TAGS][:4]}


def main() -> None:
    for caminho in sys.argv[1:]:
        nay = json.load(open(caminho, encoding="utf-8"))
        falta = [fn for fn in nay["funcoes"].values() if not fn.get("explicacao")]
        print(f"{nay['nay']}: {len(falta)} a explicar", flush=True)
        feitos = [0]

        def um(fn):
            x = explicar(nay, fn)
            with trava:
                if "falha" not in x:
                    fn.update(x)
                feitos[0] += 1
                if feitos[0] % 40 == 0:
                    json.dump(nay, open(caminho, "w", encoding="utf-8"), ensure_ascii=False)
                    print(f"  {nay['nay']}: {feitos[0]}/{len(falta)}", flush=True)

        with ThreadPoolExecutor(8) as ex:
            list(ex.map(um, falta))
        json.dump(nay, open(caminho, "w", encoding="utf-8"), ensure_ascii=False)
        sem = sum(1 for fn in nay["funcoes"].values() if not fn.get("explicacao"))
        print(f"{nay['nay']}: pronto ({sem} sem explicação)", flush=True)


if __name__ == "__main__":
    main()
