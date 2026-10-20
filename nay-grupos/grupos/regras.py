"""As regras que ele ajusta sem mexer no código (config.json), com o padrão e a conferência.

Pedro, 09/10/2026: "Pesos padrão (editáveis em arquivo de configuração, sem mexer no código)"; "os cortes
(90 e 70) ficam na configuração"; "ignorar pedidos com mais de 48h (configurável)".

Arquivo estragado não derruba o serviço: vale o padrão e o aviso aparece na tela.
"""
from __future__ import annotations

import copy
import json
import os

PADRAO = {
    "modo": "treino",
    "envio_manual": True,
    "janela_h": 48,
    "pesos": {"preco": 40, "local": 20, "quartos": 15, "mobiliado": 10, "andar": 10, "extras": 5, "elevador": 35},
    "cortes": {"verde": 90, "amarelo": 70},
    "preco": {"cheio_ate_abaixo": 0.15, "zera_em": 0.40, "tolerancia_acima": 0.10, "rend_no_limite_acima": 90},
    "local": {"exato": 100, "divisa_colado": 85, "divisa_piso": 45, "perto_sem_divisa": 65, "perto_ate_km": 5,
              "km_que_zera": 10, "vizinho_a_mao": 65, "mesmo_bairro_outro_condominio": 50},
    "quartos": {"igual": 100, "um_a_mais": 60},
    "mobiliado": {"atende": 100, "semi": 50, "nao_atende": 0, "nao_informado": 50},
    "confirmado_dias": 30,
    "alternativas": 4,
    "limite_de_leituras_por_dia": 6000,
    "intervalo_min_entre_envios": 0,          # 15/10 (Pedro): sem espera entre mensagens ao mesmo corretor
    "mensagem_de_abertura": ("Oi, vi sua solicitação no grupo, tenho um imóvel que pode se encaixar no que o seu "
                             "cliente quer, vou te enviar aqui ok? Qualquer dúvida me avisa"),
    "enviar_dados_e_fotos": True,
    # 19/10 (Pedro: "pode ativar um envio automático para o corretor que pediu, em imóveis com a nota acima de 88 ...
    # pode botar para chamar o corretor no PV pelo número da Parceria no automático"): com modo "ativo"
    "nota_min_automatico": 88,
    "mensagem_automatica": "Oi, vi seu pedido lá no grupo! Veja se esse imóvel serve 😊",
    "automatico_max_dia": 40,
    "automatico_das": 8,
    "automatico_ate": 20,
    "automatico_desde": "",
}


def _juntar(padrao: dict, veio: dict, avisos: list[str], caminho: str = "") -> dict:
    """O que veio por cima do padrão, só nas chaves que existem e com o tipo certo."""
    saida = copy.deepcopy(padrao)
    for chave, valor in (veio or {}).items():
        if chave.startswith("_"):
            continue                                   # comentário do arquivo
        if chave not in padrao:
            avisos.append(f"chave desconhecida em config.json: {caminho}{chave}")
            continue
        base = padrao[chave]
        if isinstance(base, dict):
            if isinstance(valor, dict):
                saida[chave] = _juntar(base, valor, avisos, f"{caminho}{chave}.")
            else:
                avisos.append(f"{caminho}{chave} devia ser um grupo de chaves; ficou o padrão")
        elif isinstance(base, bool):
            if isinstance(valor, bool):
                saida[chave] = valor
            else:
                avisos.append(f"{caminho}{chave} devia ser true ou false; ficou o padrão")
        elif isinstance(base, (int, float)):
            if isinstance(valor, (int, float)) and not isinstance(valor, bool) and valor >= 0:
                saida[chave] = valor
            else:
                avisos.append(f"{caminho}{chave} devia ser um número; ficou o padrão")
        else:
            if isinstance(valor, str) and valor.strip():
                saida[chave] = valor.strip()
            else:
                avisos.append(f"{caminho}{chave} devia ser um texto; ficou o padrão")
    return saida


def conferir(regras: dict) -> tuple[dict, list[str]]:
    """Limites que não podem ser atravessados, e o modo que esta versão sabe fazer."""
    avisos: list[str] = []
    r = regras
    if r["modo"] not in ("treino", "ativo"):
        avisos.append(f"modo '{r['modo']}' não existe; fica treino")
        r["modo"] = "treino"
    # O MODO ATIVO (19/10, Pedro): o envio automático do melhor imóvel ao corretor que pediu, quando a nota passa de
    # `nota_min_automatico` (grupos/envio.py). Sem o botão manual ligado o banco recusa o envio, então ativo exige ele.
    if r["modo"] == "ativo" and not r["envio_manual"]:
        avisos.append("modo ativo precisa de envio_manual = true (o envio passa pela mesma função do botão); ficou treino")
        r["modo"] = "treino"
    r["nota_min_automatico"] = min(max(float(r["nota_min_automatico"]), 70.0), 100.0)
    r["automatico_max_dia"] = max(0, int(r["automatico_max_dia"]))
    r["automatico_das"] = min(max(int(r["automatico_das"]), 0), 23)
    r["automatico_ate"] = min(max(int(r["automatico_ate"]), r["automatico_das"] + 1), 24)
    if sum(r["pesos"].values()) <= 0:
        avisos.append("os pesos somam zero; ficou o padrão")
        r["pesos"] = copy.deepcopy(PADRAO["pesos"])
    if not r["cortes"]["verde"] >= r["cortes"]["amarelo"]:
        avisos.append("o corte verde ficou abaixo do amarelo; ficou o padrão")
        r["cortes"] = copy.deepcopy(PADRAO["cortes"])
    p = r["preco"]
    if not (0 < p["cheio_ate_abaixo"] < 1 and 0 <= p["zera_em"] < 1 - p["cheio_ate_abaixo"] and 0 < p["tolerancia_acima"] <= 1):
        avisos.append("as faixas de preço não fecham; ficou o padrão")
        r["preco"] = copy.deepcopy(PADRAO["preco"])
    if r["local"]["km_que_zera"] <= 0:
        avisos.append("local.km_que_zera tem de ser maior que zero; ficou o padrão")
        r["local"] = copy.deepcopy(PADRAO["local"])
    r["janela_h"] = max(1, int(r["janela_h"]))
    r["alternativas"] = max(0, min(int(r["alternativas"]), 10))
    r["confirmado_dias"] = max(1, int(r["confirmado_dias"]))
    r["limite_de_leituras_por_dia"] = max(0, int(r["limite_de_leituras_por_dia"]))
    return r, avisos


def carregar(caminho: str) -> tuple[dict, list[str]]:
    """Devolve as regras e os avisos (para a tela)."""
    avisos: list[str] = []
    veio: dict = {}
    if os.path.exists(caminho):
        try:
            with open(caminho, encoding="utf-8") as f:
                veio = json.load(f)
            if not isinstance(veio, dict):
                raise ValueError("o arquivo não é um objeto JSON")
        except (OSError, ValueError) as e:
            avisos.append(f"config.json não pôde ser lido ({e}); valendo o padrão")
            veio = {}
    else:
        avisos.append("config.json não existe; valendo o padrão")
    regras, mais = conferir(_juntar(PADRAO, veio, avisos))
    return regras, avisos + mais
