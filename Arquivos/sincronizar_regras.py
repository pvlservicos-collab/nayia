"""
Leva as regras de negócio da tabela `regras` para dentro do prompt do
agente da Nay, no fluxo `Nay- recebe mensagem` do n8n.

O PROBLEMA QUE ISSO RESOLVE (medido em 27/08/2026): a tabela `regras`
tinha 5 regras ativas -- sobre o que pode e não pode ser dito de
endereço, sobre qualificação em locação, sobre visita sem acompanhante e
sobre busca sem resultado -- e NENHUM nó de NENHUM fluxo, e nenhuma
função do banco, lia essa tabela. As regras não chegavam à Nay. É o
mecanismo de "aprendizado" que o HISTORICO-APRENDIZADO.md descreve (o
Tel corrige, a correção vira regra, a Nay passa a usar) com a tabela
pronta e ninguém do outro lado.

POR QUE SINCRONIZAR EM VEZ DE CONSULTAR EM TEMPO REAL
As regras são poucas, curtas, e valem SEMPRE -- não dependem da
pergunta do corretor. As duas alternativas de tempo real têm custo:

- Ferramenta que a Nay chama: ela pode não chamar. Aceitável para dado
  situacional (o CRECI de um corretor); inaceitável para regra de
  política que protege dado de proprietário.
- Nó de banco antes do agente: obriga inserir nó no caminho de produção,
  vira dependência dura do atendimento, e cai no padrão da Parte 4.2 do
  histórico (nó lendo nó que pode não ter rodado). Uma consulta que
  falhe passa a derrubar a resposta ao corretor.

Sincronizar troca "pode falhar toda mensagem" por "precisa de um passo
explícito quando a regra muda". A tabela continua sendo a fonte da
verdade; o prompt passa a ser uma cópia gerada dela, entre marcadores.

NÃO IMPORTA NADA SOZINHO. Escreve um arquivo corrigido e mostra o que
mudou. O import e o restart do n8n são passo separado e confirmado --
`import:workflow` desativa o fluxo e só o restart reativa (CLAUDE.md).

Uso, no servidor:
    python3 sincronizar_regras.py            # mostra o que mudaria
    python3 sincronizar_regras.py --escrever # grava /tmp/regras_patched.json
"""
import json
import subprocess
import sys

WORKFLOW_ID = "sQuiEjbEDMEbjX5U"
CONTAINER_N8N = "n8n-viux-n8n-1"
CONTAINER_PG = "nay-postgres"
SAIDA = "/tmp/regras_patched.json"

INICIO = "=== REGRAS DO TEL (bloco gerado a partir da tabela regras) ==="
FIM = "=== FIM DAS REGRAS DO TEL ==="

# Onde o bloco entra quando ainda não existe: logo antes da seção de voz,
# depois das REGRAS ZERO. Regra de política vem antes de estilo.
ANCORA = "=== COMO VOCÊ ESCREVE ==="

CABECALHO = (
    "Estas regras foram escritas pelo Tel e valem SEMPRE. Quando uma delas\n"
    "disser algo mais restritivo do que o resto deste prompt, a regra ganha.\n"
    "Você nunca menciona ao corretor que existe uma lista de regras."
)


def _docker(container, *args):
    return subprocess.run(
        ["docker", "exec", container, *args], capture_output=True, text=True
    )


def ler_regras():
    """Só as ativas, na ordem do id -- ordem estável importa para o diff
    não mudar sozinho e para o cache de prompt não ser invalidado à toa."""
    r = _docker(
        CONTAINER_PG, "psql", "-U", "nay", "-d", "naydb", "-t", "-A", "-F", "\x1f",
        "-c", "SELECT contexto, texto FROM regras WHERE ativa ORDER BY id",
    )
    if r.returncode != 0:
        raise RuntimeError("psql falhou: " + (r.stderr or r.stdout)[:300])

    regras = []
    for linha in r.stdout.strip().split("\n"):
        if not linha.strip():
            continue
        contexto, _, texto = linha.partition("\x1f")
        texto = texto.strip()
        if not texto:
            continue
        contexto = (contexto or "geral").strip()
        regras.append((contexto, texto))
    return regras


def montar_bloco(regras):
    linhas = [INICIO, CABECALHO, ""]
    for contexto, texto in regras:
        # uma regra por LINHA, sempre: o texto vem do banco e pode ter
        # quebras e espaços duplos que embaralhariam o bloco no prompt.
        linhas.append(f"[{contexto}] {' '.join(texto.split())}")
    linhas.append(FIM)
    return "\n".join(linhas)


def aplicar(prompt, bloco):
    """Idempotente: se o bloco já existe, substitui entre os marcadores;
    se não, insere antes da âncora. Rodar duas vezes seguidas com as
    mesmas regras não muda nada -- é o que torna isto seguro de repetir."""
    i = prompt.find(INICIO)
    if i != -1:
        j = prompt.find(FIM, i)
        if j == -1:
            raise RuntimeError(
                "achei o marcador de início e não o de fim -- o prompt foi "
                "editado à mão no meio do bloco gerado. Conserte lá antes."
            )
        return prompt[:i] + bloco + prompt[j + len(FIM):]

    if prompt.count(ANCORA) != 1:
        raise RuntimeError(
            f"a âncora {ANCORA!r} aparece {prompt.count(ANCORA)}x no prompt; "
            "esperava exatamente 1. Não vou adivinhar onde inserir."
        )
    return prompt.replace(ANCORA, bloco + "\n\n" + ANCORA, 1)


def exportar_fluxo():
    r = _docker(
        CONTAINER_N8N, "n8n", "export:workflow",
        f"--id={WORKFLOW_ID}", "--output=/tmp/rg_export.json",
    )
    if r.returncode != 0:
        raise RuntimeError("export:workflow falhou: " + (r.stderr or r.stdout)[:300])
    bruto = _docker(CONTAINER_N8N, "cat", "/tmp/rg_export.json").stdout
    _docker(CONTAINER_N8N, "rm", "-f", "/tmp/rg_export.json")
    return json.loads(bruto)


def main():
    escrever = "--escrever" in sys.argv

    regras = ler_regras()
    if not regras:
        # Não é erro: pode ser que o Tel tenha desativado todas. Mas apagar
        # o bloco em silêncio seria pior do que parar e perguntar.
        print("nenhuma regra ativa na tabela -- nada a fazer, nada foi tocado.")
        return 0

    dados = exportar_fluxo()
    wf = dados[0] if isinstance(dados, list) else dados
    agentes = [n for n in wf["nodes"] if n.get("name") == "AI Agent"]
    if len(agentes) != 1:
        raise RuntimeError(f"esperava 1 nó 'AI Agent', achei {len(agentes)}")

    opcoes = agentes[0]["parameters"]["options"]
    antes = opcoes["systemMessage"]
    bloco = montar_bloco(regras)
    depois = aplicar(antes, bloco)

    print(f"regras ativas: {len(regras)}")
    for contexto, texto in regras:
        print(f"  [{contexto}] {texto[:78]}{'…' if len(texto) > 78 else ''}")
    print()
    print(f"prompt: {len(antes)} -> {len(depois)} caracteres "
          f"({len(depois) - len(antes):+d})")

    if antes == depois:
        print("o prompt já está sincronizado com a tabela. Nada a fazer.")
        return 0

    if not escrever:
        print(f"\n(simulação -- rode com --escrever para gravar {SAIDA})")
        return 0

    opcoes["systemMessage"] = depois
    with open(SAIDA, "w", encoding="utf-8") as f:
        json.dump(dados, f, ensure_ascii=False, indent=2)
    print(f"\ngravado: {SAIDA}")
    print("O IMPORT É PASSO SEPARADO. import:workflow desativa o fluxo e só")
    print("o restart reativa -- as quatro linhas juntas, ver CLAUDE.md.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
