"""Gera a parte de REGRAS do `REGRAS-E-BUGS.md` a partir do banco.

POR QUE GERADO E NÃO ESCRITO À MÃO: a regra que vale é a que está na
tabela `regras`, porque é ela que o `sincronizar_regras.py` costura no
prompt da Nay. Documento escrito à mão vira uma segunda cópia, e o
CLAUDE.md já registra o que acontece com cópias: elas divergem sozinhas e
a divergência só aparece quando alguém se machuca (a gramática de comando
tinha QUATRO cópias e uma estava errada).

Aqui o texto sai do banco toda vez. O que é escrito à mão é só a segunda
metade do arquivo -- a lista de bugs --, e o gerador não encosta nela: ele
troca apenas o miolo entre as duas marcas.

    .venv/bin/python gerar_regras_e_bugs.py            # mostra o que mudaria
    .venv/bin/python gerar_regras_e_bugs.py --escrever # grava
"""
import argparse
import sys

import db

ARQUIVO = "REGRAS-E-BUGS.md"
INICIO = "<!-- REGRAS:INICIO -->"
FIM = "<!-- REGRAS:FIM -->"

# Só para dar nome de gente aos contextos crus da tabela.
TITULOS = {
    "atendimento": "Atendimento",
    "bairro": "Bairro e região",
    "disponibilidade": "Disponibilidade",
    "endereco": "Endereço e número da unidade",
    "escalacao": "Quando escalar ao Tel",
    "geral": "Geral",
    "grupo": "Grupos e cadastro",
    "identidade": "Quem é quem",
    "locacao": "Locação",
    "pendencia": "Pendências",
    "prospeccao": "Prospecção e oferta",
    "tom": "Tom",
    "visita": "Visita",
}


def buscar(conexao):
    with conexao.cursor() as cur:
        cur.execute(
            "SELECT id, coalesce(NULLIF(btrim(contexto),''),'geral') AS contexto, texto "
            "  FROM regras WHERE ativa "
            " ORDER BY coalesce(NULLIF(btrim(contexto),''),'geral'), id")
        return cur.fetchall()


def montar(regras):
    linhas = [
        "",
        f"*Geradas de `regras` (tabela do banco) por `gerar_regras_e_bugs.py`. "
        f"São {len(regras)} regras ativas. Para mudar uma, mude no banco e rode "
        "o gerador -- editar aqui à mão não muda o que a Nay lê.*",
        "",
    ]
    atual = None
    for r in regras:
        if r["contexto"] != atual:
            atual = r["contexto"]
            linhas.append("")
            linhas.append(f"### {TITULOS.get(atual, atual.capitalize())}")
            linhas.append("")
        linhas.append(f"- **[{r['id']}]** {r['texto'].strip()}")
    linhas.append("")
    return "\n".join(linhas)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--escrever", action="store_true")
    args = p.parse_args()

    conexao = db.conectar()
    try:
        regras = buscar(conexao)
    finally:
        conexao.close()

    with open(ARQUIVO, encoding="utf-8") as f:
        texto = f.read()

    if INICIO not in texto or FIM not in texto:
        print(f"ERRO: {ARQUIVO} não tem as marcas {INICIO} / {FIM}.")
        return 1

    antes = texto.split(INICIO)[0]
    depois = texto.split(FIM)[1]
    novo = antes + INICIO + montar(regras) + FIM + depois

    if novo == texto:
        print(f"{ARQUIVO} já está em dia ({len(regras)} regras).")
        return 0

    if not args.escrever:
        print(f"{len(regras)} regras ativas; {ARQUIVO} está diferente do banco.")
        print("(simulação -- rode com --escrever para gravar)")
        return 0

    with open(ARQUIVO, "w", encoding="utf-8") as f:
        f.write(novo)
    print(f"{ARQUIVO} atualizado com {len(regras)} regras.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
