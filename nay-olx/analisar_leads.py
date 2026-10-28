"""AS BUSCAS DOS LEADS (Pedro, 28/10/2026, 510): "analisar toda a aba leads, seguindo os princípios de nota de quanto o
imóvel se encaixa com o pedido do corretor nos grupos, mas vai encontrar todas as solicitações de leads e ver se tem
algum dos nossos imóveis que faz sentido enviar para esses leads, é claro que ainda não foi enviado, e deixar salvo
essas buscas do lead como um cardzinho no contato deles".

Os pedidos abaixo foram tirados À MÃO da conversa de cada lead (captacao_mensagens, 16 a 28/10), porque os filtros que
a Nay gravou estão pela metade (sem valor, sem bairro, 20 leads sem nada). Ficaram de fora os que não procuram imóvel:
corretor oferecendo parceria, proprietário, inquilino, fornecedor, bot de outra empresa.

A nota é a da Captação ativa com o aperto da busca do cliente (olx/buscas.py opcoes_da_base): bairro pedido e vizinho
colado (divisa até VIZINHO_ATE_KM), valor de 20% abaixo a 10% acima do teto, nota a partir do corte amarelo, só o que
pode ir a ele (olx_imovel_vai_ao_cliente), fora o que já foi (olx_cliente_enviada, os cards da conversa, as ofertas da
busca e o anúncio de onde ele veio). Abaixo do mínimo que atendemos (busca_venda_min / busca_aluguel_min), o card diz
isso e não procura.

Refaz tudo a cada rodada (apaga as buscas do lead e grava de novo):
    cd /root/nay-olx && set -a && . ./.env && set +a && .venv/bin/python analisar_leads.py [--so 41,45] [--ensaio]
"""
import argparse
import json
import re
from datetime import datetime, timedelta, timezone

from olx import banco, buscas, whatsapp
from olx import busca_olx as bo

QUANTAS = 5

# lead -> [(o que ele disse, filtros)]. "andar" vai direto ao pedido da nota (os filtros da Nay não têm andar).
PEDIDOS: dict[int, list[tuple[str, dict]]] = {
    2: [("Apartamento até R$ 3 mil, da Constantino Nery até a Ponta Negra, com modulados e ar; quarto com armário",
         {"finalidade": "locacao", "tipo": "apartamento", "teto": 3000, "quartos": 2, "mobilia": "semi",
          "bairros": ["Chapada", "São Jorge", "Dom Pedro", "Planalto", "Alvorada", "Ponta Negra"]})],
    3: [("Veio pelo Kopenhagen (Parque 10, 2 quartos, R$ 270 mil); perguntou se aceita financiamento",
         {"finalidade": "venda", "tipo": "apartamento", "teto": 270000, "quartos": 2, "bairros": ["Parque 10 de Novembro"],
          "financiamento": "simular"})],
    4: [("Veio pelo Turim (Ponta Negra, 2 quartos, R$ 3 mil, mobiliado); quer outras opções parecidas",
         {"finalidade": "locacao", "tipo": "apartamento", "teto": 3000, "quartos": 2, "mobilia": "mobiliado",
          "bairros": ["Ponta Negra"]})],
    5: [("Veio pelo Acquarelle (Ponta Negra, 3 quartos, R$ 630 mil); perguntou o andar",
         {"finalidade": "venda", "tipo": "apartamento", "teto": 630000, "quartos": 3, "bairros": ["Ponta Negra"]})],
    6: [("Casa em condomínio, 2 quartos e 2 vagas, Ponta Negra, Planalto ou Dom Pedro, no máximo R$ 7 mil",
         {"finalidade": "locacao", "tipo": "casa_condominio", "teto": 7000, "quartos": 2, "mobilia": "semi",
          "bairros": ["Ponta Negra", "Planalto", "Dom Pedro"]})],
    7: [("Veio pelo Acácias (Japiim, 2 quartos, R$ 190 mil); quer simular financiamento",
         {"finalidade": "venda", "tipo": "apartamento", "teto": 190800, "quartos": 2, "bairros": ["Japiim"],
          "financiamento": "simular"})],
    9: [("1 quarto com suíte até R$ 300 mil, quanto mais perto da UFAM melhor; perguntou de financiamento",
         {"finalidade": "venda", "tipo": "apartamento", "teto": 300000, "quartos": 1, "financiamento": "simular",
          "bairros": ["Coroado", "Aleixo", "Japiim", "Parque 10 de Novembro", "Petrópolis"]})],
    10: [("Casa em condomínio até uns R$ 900 mil, 3 quartos com suíte, de preferência térrea, perto de Flores; "
          "100% mobiliada; dá apartamento de entrada e financia o resto",
          {"finalidade": "venda", "tipo": "casa_condominio", "teto": 900000, "quartos": 3, "bairros": ["Flores"],
           "financiamento": "simular"})],
    14: [("Casa em condomínio, 3 quartos (veio pelo Residencial Tarumã, R$ 650 mil); não muito afastada",
          {"finalidade": "venda", "tipo": "casa_condominio", "teto": 650000, "quartos": 3, "bairros": ["Tarumã"]})],
    15: [("Casa compacta em condomínio fechado, 3 quartos, até R$ 1 milhão, Parque 10 e adjacências (para a cliente dele)",
          {"finalidade": "venda", "tipo": "casa_condominio", "teto": 1000000, "quartos": 3,
           "bairros": ["Parque 10 de Novembro"], "financiamento": "simular"})],
    16: [("Apartamento de 2 a 3 quartos com 2 banheiros, até R$ 460-470 mil, Parque 10 e Flores (perguntou do View Club)",
          {"finalidade": "venda", "tipo": "apartamento", "teto": 470000, "quartos": 2,
           "bairros": ["Parque 10 de Novembro", "Flores"]})],
    17: [("Casa em condomínio, 3 quartos, até R$ 1 milhão, Flores, Parque 10 ou Laranjeiras; a do Atlantis precisa de reforma",
          {"finalidade": "venda", "tipo": "casa_condominio", "teto": 1000000, "quartos": 3,
           "bairros": ["Parque 10 de Novembro", "Flores"]})],
    18: [("Apartamento no Planalto (busca no Mosaico) de R$ 250 a 270 mil, no máximo 2º andar (criança autista), "
          "financiamento pela Caixa, FGTS",
          {"finalidade": "venda", "tipo": "apartamento", "teto": 270000, "quartos": 2, "bairros": ["Planalto"],
           "financiamento": "simular", "andar": ["térreo", "1", "2"]})],
    19: [("Casa em condomínio na área do Tarumã, uns R$ 250 mil, simulação de financiamento",
          {"finalidade": "venda", "tipo": "casa_condominio", "teto": 250000, "quartos": 2, "bairros": ["Tarumã"],
           "financiamento": "simular"})],
    20: [("Apartamento de 1 ou 2 quartos até R$ 190 mil, entre o Centro e o Japiim, com garagem, financiamento/MCMV",
          {"finalidade": "venda", "tipo": "apartamento", "teto": 190000, "quartos": 1, "financiamento": "simular",
           "bairros": ["Centro", "Aparecida", "Praça 14 de Janeiro", "Cachoeirinha", "Educandos", "Japiim"]})],
    21: [("Veio pelo Leve Castanheiras (São José Operário, 2 quartos, R$ 230 mil)",
          {"finalidade": "venda", "tipo": "apartamento", "teto": 230000, "quartos": 2, "bairros": ["São José Operário"]})],
    22: [("Casa em condomínio na Ponta Negra (veio pelo Bosque das Palmas, R$ 5.500); \"manda o que você tem\"",
          {"finalidade": "locacao", "tipo": "casa_condominio", "teto": 5500, "quartos": 3, "bairros": ["Ponta Negra"]})],
    25: [("Veio pelo Kopenhagen (Parque 10, 2 quartos, R$ 270 mil); quer financiar",
          {"finalidade": "venda", "tipo": "apartamento", "teto": 270000, "quartos": 2, "bairros": ["Parque 10 de Novembro"],
           "financiamento": "simular"})],
    28: [("Apartamento mobiliado de 2 quartos até R$ 5 mil, perto do Girassol, Alegra River Park, CT do Manaura",
          {"finalidade": "locacao", "tipo": "apartamento", "teto": 5000, "quartos": 2, "mobilia": "mobiliado",
           "bairros": ["Colônia Terra Nova"]})],
    31: [("Terreno na Ponta Negra (veio pelo lote do Passaredo, R$ 277 mil); oferece uma lancha na troca",
          {"finalidade": "venda", "tipo": "terreno", "teto": 277000, "bairros": ["Ponta Negra"]})],
    34: [("Casa em condomínio, 3 quartos, Parque 10 (veio pelo Atlantis, R$ 1.295.000)",
          {"finalidade": "venda", "tipo": "casa_condominio", "teto": 1295000, "quartos": 3,
           "bairros": ["Parque 10 de Novembro"]})],
    35: [("Veio pelo Smile Parque das Flores (2 quartos, R$ 3.200 de aluguel); vai visitar",
          {"finalidade": "locacao", "tipo": "apartamento", "teto": 3200, "quartos": 2, "bairros": ["Flores"]})],
    39: [("Apartamento de 4 quartos, até R$ 1 milhão, só na Ponta Negra (perguntou do Piazza dell'Acqua)",
          {"finalidade": "venda", "tipo": "apartamento", "teto": 1000000, "quartos": 4, "bairros": ["Ponta Negra"]})],
    41: [("Apartamento de 3 quartos no Adrianópolis até R$ 1 milhão, financiado (Vila de France, Singolare, "
          "Príncipe de Gales; perguntou do Saint Marie)",
          {"finalidade": "venda", "tipo": "apartamento", "teto": 1000000, "quartos": 3, "bairros": ["Adrianópolis"],
           "financiamento": "simular",
           "referencias": ["Vila de France", "Singolare", "Príncipe de Gales", "Sainte Marie"]})],
    44: [("Apartamento de 3 quartos na Ponta Negra para a mãe, com urgência (5 dias para sair); veio pelo Acquarelle "
          "(R$ 630 mil), não quis o Ilhas Gregas, quer o Reserva das Praias",
          {"finalidade": "venda", "tipo": "apartamento", "teto": 650000, "quartos": 3, "bairros": ["Ponta Negra"]}),
         ("Reserva das Praias (o condomínio que a mãe quer)",
          {"finalidade": "venda", "tipo": "apartamento", "teto": 650000, "quartos": 3, "bairros": ["Ponta Negra"],
           "condominio": "Reserva das Praias"})],
    45: [("Apartamento de 3 quartos, bem conservado, até R$ 700-750 mil, Parque 10, Vieiralves e Mundi",
          {"finalidade": "venda", "tipo": "apartamento", "teto": 750000, "quartos": 3, "aceita_parceiro": "true",
           "bairros": ["Parque 10 de Novembro", "Aleixo", "Adrianópolis", "Nossa Senhora das Graças"]})],
    51: [("Casa de 3 quartos até R$ 150 mil (Cachoeirinha, Petrópolis, São Francisco, Aleixo, Japiim, Adrianópolis), "
          "pode ser na beira da pista",
          {"finalidade": "venda", "tipo": "casa", "teto": 150000, "quartos": 3, "financiamento": "simular",
           "bairros": ["Cachoeirinha", "Petrópolis", "São Francisco", "Aleixo", "Japiim", "Adrianópolis"]})],
    52: [("Apartamento mobiliado (cozinha e lavanderia completas), 3 quartos, R$ 3,5 a 4 mil com condomínio, aceita "
          "pet (2 gatas), perto do Distrito; Ponta Negra é longe",
          {"finalidade": "locacao", "tipo": "apartamento", "teto": 4000, "quartos": 3, "mobilia": "mobiliado",
           "qualquer_bairro": True, "perto_de": "Distrito Industrial"})],
    53: [("Casa em condomínio, 3 quartos, até R$ 6 mil (um pouco mais com energia solar), quanto mais mobília melhor",
          {"finalidade": "locacao", "tipo": "casa_condominio", "teto": 6000, "quartos": 3, "mobilia": "mobiliado"})],
    54: [("Casa em condomínio de 4 quartos com área externa (veio pelo Bosque das Palmas; gostou do 9024)",
          {"finalidade": "locacao", "tipo": "casa_condominio", "quartos": 4, "bairros": ["Ponta Negra"]})],
    55: [("Apartamento no TÉRREO, Planalto (veio pelo Vista das Mangueiras, R$ 250 mil); entrada pequena, quer dar o "
          "dele (Vista do Sol) no negócio",
          {"finalidade": "venda", "tipo": "apartamento", "teto": 250000, "quartos": 2, "bairros": ["Planalto"],
           "financiamento": "simular", "andar": ["térreo"]})],
    58: [("Apartamento de 3 quartos para alugar no Parque 10 (veio pelo Edifício Firenze, R$ 5 mil)",
          {"finalidade": "locacao", "tipo": "apartamento", "teto": 5000, "quartos": 3,
           "bairros": ["Parque 10 de Novembro"]})],
    59: [("Casa em condomínio de 2 quartos, aceita pet (veio pelo Sausalito, Parque 10, R$ 300 mil)",
          {"finalidade": "venda", "tipo": "casa_condominio", "teto": 300000, "quartos": 2,
           "bairros": ["Parque 10 de Novembro"]})],
    60: [("Casa para alugar só no Ponta Negra Village, R$ 6 a 7 mil, com modulados e ar",
          {"finalidade": "locacao", "tipo": "casa_condominio", "teto": 7000, "mobilia": "semi", "bairros": ["Ponta Negra"],
           "condominio": "Ponta Negra Village"})],
    61: [("Veio pela casa do Dom Pedro (#2683, 3 quartos, R$ 420 mil); quer a localização",
          {"finalidade": "venda", "tipo": "casa", "teto": 420000, "quartos": 3, "bairros": ["Dom Pedro"]})],
    63: [("Mora de aluguel no Prime Arena (Chapada) e perguntou do #3176 (2 quartos, R$ 350 mil)",
          {"finalidade": "venda", "tipo": "apartamento", "teto": 350000, "quartos": 2, "bairros": ["Chapada"]})],
    64: [("Apartamento de 3 quartos para alugar (visitou o Mont Clair, Adrianópolis, R$ 3.700)",
          {"finalidade": "locacao", "tipo": "apartamento", "teto": 3700, "quartos": 3, "bairros": ["Adrianópolis"]})],
    65: [("Casa de 4 quartos na Zona Leste, sem móveis, perto de R$ 2.900",
          {"finalidade": "locacao", "tipo": "casa", "teto": 2900, "quartos": 4, "mobilia": "sem",
           "bairros": ["Armando Mendes", "Colônia Antônio Aleixo", "Gilberto Mestrinho", "Jorge Teixeira", "Mauazinho",
                       "São José Operário", "Tancredo Neves", "Zumbi dos Palmares"]})],
    67: [("Casa no Bosque das Palmas (Ponta Negra), pediu por R$ 4 mil",
          {"finalidade": "locacao", "tipo": "casa_condominio", "teto": 4000, "quartos": 3, "bairros": ["Ponta Negra"]})],
    70: [("Veio pelo Kopenhagen (Parque 10, 2 quartos, R$ 270 mil); quer visitar e outras opções parecidas",
          {"finalidade": "venda", "tipo": "apartamento", "teto": 270000, "quartos": 2,
           "bairros": ["Parque 10 de Novembro"]})],
}

# o que ele já conhece sem ter ido por aqui (falou do anúncio sem colar o link)
JA_CONHECE: dict[int, list[int]] = {
    55: [5741],     # "Vi o anúncio do ap Vista das Mangueiras no térreo" (24/10)
}

TIPO = {"apartamento": "Apartamento", "casa_condominio": "Casa em condomínio", "casa": "Casa", "terreno": "Terreno"}


def reais(v) -> str:
    return "R$ " + f"{int(v):,}".replace(",", ".")


def titulo(f: dict) -> str:
    partes = ["VENDA" if f.get("finalidade") == "venda" else "ALUGUEL", TIPO.get(f.get("tipo"), f.get("tipo") or "")]
    if f.get("quartos"):
        partes.append(f"{f['quartos']} quarto{'s' if int(f['quartos']) > 1 else ''}")
    if f.get("teto"):
        partes.append("até " + reais(f["teto"]))
    if f.get("condominio"):
        partes.append(f["condominio"])
    elif f.get("perto_de"):
        partes.append("perto do " + f["perto_de"])
    elif f.get("bairros"):
        partes.append(", ".join(f["bairros"][:3]) + ("…" if len(f["bairros"]) > 3 else ""))
    return " · ".join(p for p in partes if p)


def ja_foram(conn, lead: dict) -> set[int]:
    """O que já foi a ele: os envios da Nay, os cards da conversa (inclusive os da equipe), as ofertas da busca e o
    anúncio de onde ele veio."""
    cods = {int(r["codigo"]) for r in banco.linhas(conn, "SELECT DISTINCT codigo FROM privado.olx_cliente_enviada "
                                                         "WHERE lead = %s AND codigo IS NOT NULL", (lead["id"],))}
    conversa = banco.linhas(conn, """SELECT direcao, texto FROM captacao_mensagens
                                      WHERE right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = right(%s, 8)
                                      ORDER BY criada_em""", (lead["telefone"],))
    enviadas = [m["texto"] for m in conversa if m["direcao"] == "enviada"]
    enviadas += [e["texto"] for e in whatsapp.da_equipe_no_crm(whatsapp._so8(lead["telefone"]), limite=200)]
    for t in enviadas:
        cods |= {int(c) for c in re.findall(r"(?:C[óo]digo:?\s*|#)(\d{3,5})\b", t or "", re.I)}
    # o anúncio que ELE colou (o link do site ou da OLX): é por esse que ele veio
    for m in conversa:
        if m["direcao"] == "recebida":
            cods |= {int(c) for c in re.findall(r"imobeasy\.com/imoveis/(\d{3,5})", m["texto"] or "")}
    cods |= set(whatsapp.codigos_dos_links(conn, conversa, ate=50))
    for r in banco.linhas(conn, "SELECT ofertas FROM privado.busca_cliente WHERE lead = %s", (lead["id"],)):
        cods |= {int(c) for c in re.findall(r'"codigo":\s*(\d+)', json.dumps(r["ofertas"] or []))}
    if lead.get("codigo"):
        cods.add(int(lead["codigo"]))
    return cods | set(JA_CONHECE.get(lead["id"], []))


def avaliar(conn, lead: dict, f: dict, fora: set[int], regras, catalogo, vizinhos) -> tuple[list[dict], str | None]:
    """opcoes_da_base, guardando o porquê da nota de cada imóvel."""
    imoveis = catalogo
    pedido = bo.pedido_dos_filtros(f, bo.glugares.Lugares(conn), da_base=True)
    if f.get("andar"):
        pedido["andar"] = f["andar"]
    if not pedido.get("tipo"):
        imoveis = [i for i in imoveis if i["tipo"] in ("apartamento", "casa")]
    if "condom" in str(f.get("tipo") or "").lower():
        imoveis = [i for i in imoveis if "condom" in bo.normal(i.get("tipo_cadastro"))]
    if f.get("condominio"):
        alvo = bo.normal(f["condominio"])
        imoveis = [i for i in imoveis if alvo in bo.normal(i.get("condominio"))]
    imoveis = [i for i in imoveis if int(i["codigo"]) not in fora]
    teto = pedido.get("preco_max")
    if teto:
        valor = "valor_venda" if pedido.get("operacao") == "venda" else "valor_aluguel"
        imoveis = [i for i in imoveis if i.get(valor)
                   and teto * (1 - buscas.FAIXA_ABAIXO) <= i[valor] <= teto * (1 + buscas.FAIXA_ACIMA)]
    if not imoveis:
        return [], "nenhum imóvel nosso no tipo e na faixa de valor (de 20% abaixo a 10% acima do teto) que ainda não foi"
    viz = {a: {b: v for b, v in vs.items() if v.get("km") is None or (v.get("divisa") and v["km"] <= buscas.VIZINHO_ATE_KM)}
           for a, vs in vizinhos.items()}
    # 28/10 (Tel): quem veio de condomínio recente pesa o padrão do condomínio na nota (buscas.com_padrao)
    padrao = buscas.quer_recente(conn, lead, f)
    regras = {**regras, "alternativas": 200 if padrao else QUANTAS * 4}
    limite = datetime.now(timezone.utc) - timedelta(days=regras["confirmado_dias"])
    r = bo.gpontuar.melhores(pedido, imoveis, regras, viz, limite)
    if padrao:
        r["pares"] = buscas.com_padrao(r["pares"], buscas.recentes(conn, [p["codigo"] for p in r["pares"]]), padrao)
    perto = {x["bairro"] for x in whatsapp.so_perto(conn, [{"bairro": p["imovel"].get("bairro")} for p in r["pares"]], f)}
    saida, melhor = [], None
    for p in r["pares"]:
        melhor = p["nota"] if melhor is None else melhor
        if p["nota"] < regras["cortes"]["amarelo"] or len(saida) >= QUANTAS:
            break
        if f.get("perto_de") and p["imovel"].get("bairro") not in perto:
            continue
        if whatsapp._ofertavel(conn, int(p["codigo"]), lead):
            saida.append({"codigo": int(p["codigo"]), "nota": p["nota"],
                          "detalhe": [{k: d.get(k) for k in ("criterio", "texto", "peso", "pontos")} for d in p["detalhe"]]})
    if saida:
        return saida, None
    if r.get("motivo"):
        return [], r["motivo"]
    if melhor is not None and melhor < regras["cortes"]["amarelo"]:
        return [], f"o melhor que sobrou teve nota {melhor:.0f}, abaixo de {regras['cortes']['amarelo']}"
    return [], "os que passaram na nota não podem ir a ele (parceiro, indisponível ou longe do lugar pedido)"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--so", default="")
    ap.add_argument("--ensaio", action="store_true", help="mostra e não grava")
    a = ap.parse_args()
    so = {int(x) for x in a.so.split(",") if x.strip()}
    conn = banco.conectar()
    conn.autocommit = False
    cfg = {r["chave"]: r["valor"] for r in banco.linhas(conn, "SELECT chave, valor FROM privado.olx_config")}
    venda_min = float(cfg.get("busca_venda_min") or 200000)
    aluguel_min = float(cfg.get("busca_aluguel_min") or 2000)
    regras, _ = bo.gregras.carregar(bo.REGRAS_DOS_GRUPOS)
    so_nossos, vizinhos = bo.gcatalogo.carregar(conn, com_parceiro=False)
    com_parceiro, _ = bo.gcatalogo.carregar(conn, com_parceiro=True)
    for lid, pedidos in PEDIDOS.items():
        if so and lid not in so:
            continue
        lead = whatsapp._lead(conn, lid)
        if not lead:
            print(f"lead {lid}: não existe")
            continue
        fora = ja_foram(conn, lead)
        if not a.ensaio:
            banco.um(conn, "DELETE FROM privado.lead_busca WHERE lead_id = %s", (lid,))
        for n, (disse, f) in enumerate(pedidos, 1):
            minimo = venda_min if f.get("finalidade") == "venda" else aluguel_min
            if f.get("teto") and float(f["teto"]) < minimo:
                achados, motivo, situacao = [], f"abaixo do mínimo que atendemos ({reais(minimo)})", "abaixo_do_minimo"
            else:
                cat = com_parceiro if f.get("aceita_parceiro") == "true" else so_nossos
                achados, motivo = avaliar(conn, lead, f, fora, regras, cat, vizinhos)
                situacao = "com_opcoes" if achados else "sem_opcoes"
            print(f"lead {lid} #{n} {titulo(f)}: " + (", ".join(f"{x['codigo']} ({x['nota']:.0f})" for x in achados)
                                                       or f"nada — {motivo}"))
            if a.ensaio:
                continue
            bid = banco.um(conn, """INSERT INTO privado.lead_busca (lead_id, telefone, ordem, titulo, disse, filtros, situacao,
                                       motivo, ja_enviados) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s) RETURNING id""",
                           (lid, lead["telefone"], n, titulo(f), disse, json.dumps(f, ensure_ascii=False), situacao, motivo,
                            sorted(fora)))
            for pos, x in enumerate(achados, 1):
                banco.um(conn, """INSERT INTO privado.lead_busca_imovel (busca_id, posicao, codigo, nota, detalhe)
                                  VALUES (%s, %s, %s, %s, %s)""",
                         (bid, pos, x["codigo"], x["nota"], json.dumps(x["detalhe"], ensure_ascii=False)))
        conn.commit()
    conn.commit()


if __name__ == "__main__":
    main()
