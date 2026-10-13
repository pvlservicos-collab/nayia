"""O LUGAR DA NAY DA OLX.

Pedro, 13/10/2026: "futuramente vou criar uma nay só para responder na olx então já deixa as funções prontas".

Tudo em volta está pronto: a mensagem do cliente chega (CRM), a fila diz quem espera (olx/chat.py), o contexto traz
o anúncio, o imóvel e a conversa, e `chat.responder` manda no chat da OLX e grava. O que falta é só ISTO: ler o
contexto e decidir o que dizer. É esta função.

HOJE ELA NÃO RESPONDE NADA (devolve None), e a chave `nay_responde` nasce em `nao`: nenhuma conversa é respondida
sozinha. Quando a Nay da OLX existir, o cérebro dela entra em `decidir` (o prompt, o modelo, as paredes) e a chave
liga pela tela do CRM.

O QUE `decidir` RECEBE (olx_nay_contexto, migração 364):
  {
    "chat": 12, "conta": "proprietarios", "list_id": "1455102864",
    "cliente":  {"nome": ..., "telefone": ..., "email": ...},
    "anuncio":  {"codigo": 3050, "negocio": "venda", "titulo": ..., "preco": ..., "url": ...}   ou null
    "imovel":   o que a página pública do imóvel mostra (tipo, quartos, valores, condomínio, fotos, link)  ou null
    "mensagens": [{"de": "comprador" | "nos" | "sistema", "texto": ..., "quando": ..., "por": ...}, ...]
  }
  `anuncio` e `imovel` vêm vazios quando a conversa é de um anúncio que não subiu por aqui (feito à mão no site).

O QUE ELA DEVOLVE:
  None                                  não responde (a conversa continua esperando, visível no CRM)
  Decisao(baloes=["...", "..."])        responde, um balão de cada vez
  Decisao(passar_para_gente="motivo")   não é com ela: a conversa fica com a equipe até alguém devolver
  (as duas coisas juntas valem: responde e passa)
"""
from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class Decisao:
    baloes: list[str] = field(default_factory=list)
    passar_para_gente: str | None = None


def decidir(contexto: dict) -> Decisao | None:
    """A Nay da OLX ainda não existe: ninguém é respondido sozinho."""
    return None
