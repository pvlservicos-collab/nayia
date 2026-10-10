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
    "pesos": {"preco": 40, "local": 20, "quartos": 15, "mobiliado": 10, "andar": 10, "extras": 5},
    "cortes": {"verde": 90, "amarelo": 70},
    "preco": {"cheio_ate_abaixo": 0.20, "zera_em": 0.40, "tolerancia_acima": 0.10},
    "local": {"exato": 100, "divisa_colado": 85, "divisa_piso": 45, "perto_sem_divisa": 65, "perto_ate_km": 5,
              "km_que_zera": 10, "vizinho_a_mao": 65, "mesmo_bairro_outro_condominio": 50},
    "quartos": {"igual": 100, "um_a_mais": 60},
    "mobiliado": {"atende": 100, "semi": 50, "nao_atende": 0},
    "confirmado_dias": 30,
    "alternativas": 4,
    "limite_de_leituras_por_dia": 6000,
    "intervalo_min_entre_envios": 30,
    "mensagem_de_abertura": ("Oi, vi sua solicitação no grupo, tenho um imóvel que pode se encaixar no que o seu "
                             "cliente quer, vou te enviar aqui ok? Qualquer dúvida me avisa"),
    "enviar_dados_e_fotos": True,
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
    if r["modo"] == "ativo":
        # O MODO ATIVO (envio automático) NÃO EXISTE NESTA VERSÃO. Escrever "ativo" no arquivo não liga envio
        # nenhum: grupos/envio.py recusa sempre. Fica treino, com o aviso na tela. O que existe é o envio MANUAL
        # (`envio_manual`): o botão da tela, um clique dele por pedido, pela caixa da Nay.
        avisos.append("o arquivo pede modo ativo, mas esta versão só tem o treino: nada é enviado sozinho")
        r["modo"] = "treino"
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
