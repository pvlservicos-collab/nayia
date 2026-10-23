"""O MODELO DE CADASTRO: o que a Nay precisa saber de um imóvel, por tipo, e em que ordem pergunta.

É a aba "Editar imóvel" do site (imob-easy/assets/js/imovel-editar.js) virada pergunta: as famílias de tipo são as do
`POR_TIPO` de lá (vertical, sala, casa, terreno, outro), as chaves são as da API do site (POST/PUT /admin/api/imoveis)
e o "essencial" é o da régua do banco (nai_imovel_pontos, migração 244).

Pedro, 20/10/2026: "tem itens de cadastro que são gerais, e tem itens de cadastro que dependem do tipo de imóvel ... ela
vai perguntar o condomínio; se já tivermos um, ela não vai mais perguntar coisas desse condomínio porque já temos as
informações; se ela tiver que cadastrar um condomínio novo, aí vai pedir as coisas de condomínio".

A ficha é um dicionário plano com as chaves da API. Prefixos: `p:` vai para "privado" (torre, bloco, unidade, casa, lote),
`x:` para "extras", `c:` é do condomínio novo. Chaves que começam com `_` são da conversa, não do imóvel.
Este módulo não fala com banco nem com modelo: recebe a ficha e diz o que falta.
"""
from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from typing import Callable

# os tipos como o cadastro escreve (nai_tipo_canonico)
TIPOS = ("Apartamento", "Casa", "Casa de condomínio", "Cobertura", "Flat", "Sala/Andar", "Loja/Ponto", "Galpão",
         "Lote", "Lote em Condomínio", "Chácara", "Prédio")
MOBILIA = ("sem nada", "só climatizado", "com modulados e ar", "mobiliado")


def sem_acento(t: str | None) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", t or "") if unicodedata.category(c) != "Mn").lower()


def familia(tipo: str | None) -> str:
    """As famílias do imovel-editar.js (JS:278), testadas na mesma ordem."""
    t = sem_acento(tipo)
    if re.search(r"apartamento|flat|cobertura|studio|kitnet|loft", t):
        return "vertical"
    if re.search(r"sala|loja|ponto|conjunto|escritorio", t):
        return "sala"
    if re.search(r"casa|chacara|sitio|fazenda|sobrado", t):
        return "casa"
    if re.search(r"lote|terreno", t):
        return "terreno"
    return "outro"


def tipo_canonico(texto: str | None) -> str | None:
    """"apto", "ap", "casa em condomínio", "sala comercial" -> o tipo do cadastro."""
    t = sem_acento(texto)
    if not t.strip():
        return None
    regras = (
        (r"lote.*condom|terreno.*condom", "Lote em Condomínio"),
        (r"casa.*condom|condominio.*casa|casa de cond", "Casa de condomínio"),
        (r"cobertura", "Cobertura"), (r"\bflat\b|\bstudio\b|kitnet|\bloft\b", "Flat"),
        (r"apartamento|\bapto?\b|\bap\b", "Apartamento"),
        (r"\bsalas?\b|escritorio|andar corporativo", "Sala/Andar"), (r"\bloja|\bponto\b", "Loja/Ponto"),
        (r"galpao|deposito", "Galpão"), (r"predio", "Prédio"), (r"chacara|sitio", "Chácara"),
        (r"\blote|terreno", "Lote"), (r"\bcasa|sobrado", "Casa"),
    )
    for padrao, tipo in regras:
        if re.search(padrao, t):
            return tipo
    return None


def tem(ficha: dict, chave: str) -> bool:
    v = ficha.get(chave)
    return v not in (None, "", [], {})


def em_condominio(ficha: dict) -> bool:
    """O imóvel fica num condomínio: apartamento sempre; casa e lote quando o tipo diz; ou ele já disse o nome."""
    return (familia(ficha.get("tipo")) == "vertical" or "condom" in sem_acento(ficha.get("tipo"))
            or tem(ficha, "condo_id") or tem(ficha, "condominio"))


def condominio_novo(ficha: dict) -> bool:
    """Ele disse o nome de um condomínio que não está cadastrado: as perguntas do condomínio entram. Com um parecido
    no cadastro ainda por confirmar ("É o Life Parque Dez?"), espera a resposta."""
    if not tem(ficha, "condominio") or tem(ficha, "condo_id"):
        return False
    return not tem(ficha, "_condo_candidato") or bool(ficha.get("_condo_nao"))


def _pergunta_confirma(ficha: dict) -> str:
    c = ficha.get("_condo_candidato") or {}
    return f"É o condomínio {c.get('nome')}" + (f", no {c['bairro']}" if c.get("bairro") else "") + "?"


def finalidade(ficha: dict) -> str | None:
    if tem(ficha, "_finalidade"):
        return ficha["_finalidade"]
    if tem(ficha, "valor_aluguel") and tem(ficha, "valor_venda"):
        return "ambos"
    if tem(ficha, "valor_aluguel"):
        return "locacao"
    if tem(ficha, "valor_venda"):
        return "venda"
    return None


def _pergunta_valor(ficha: dict) -> str:
    fin = finalidade(ficha)
    if fin == "locacao":
        return "Qual o valor do aluguel?"
    if fin == "venda":
        return "Qual o valor de venda?"
    return "Ele é para alugar ou para vender? E qual o valor?"


def _pergunta_area(ficha: dict) -> str:
    f = familia(ficha.get("tipo"))
    if f == "terreno":
        return "Qual o tamanho do terreno, em m²?"
    if f == "casa":
        return "Qual a área construída da casa, em m²?"
    return "Qual a área útil, em m²?"


def _pergunta_unidade(ficha: dict) -> str:
    f = familia(ficha.get("tipo"))
    if f == "vertical":
        return "Qual a torre ou o bloco, e o número do apartamento?"
    if f == "sala":
        return "Qual o número da sala?"
    return "Qual o número da casa (ou quadra e lote) no condomínio?"


def _unidade_preenchida(ficha: dict) -> bool:
    return any(tem(ficha, k) for k in ("p:unidade", "p:casa", "p:lote"))


def _pergunta_andar(ficha: dict) -> str:
    """Tel, 20/10: "nunca se deve pedir o número do apartamento para o corretor, só o andar, e nos que têm escada
    quantos lances de escada". O elevador vem do condomínio (`_elevador`, posto pelo serviço) ou da resposta dele.
    Tel, 23/10: "tem corretor que não passa andar ... é andar baixo, médio ou alto ... não se pergunta qual andar, só
    se é alto, médio ou baixo"."""
    elevador = ficha.get("_elevador") or ficha.get("c:elevador")
    if elevador == "sim":
        return "O andar é baixo, médio ou alto?"
    if elevador == "nao":
        return "Quantos lances de escada até ele?"
    return "O andar é baixo, médio ou alto? E, se o prédio não tiver elevador, quantos lances de escada?"


def _andar_preenchido(ficha: dict) -> bool:
    return tem(ficha, "andar") or tem(ficha, "x:lances de escada")


def _area_preenchida(ficha: dict) -> bool:
    if familia(ficha.get("tipo")) == "terreno":
        return tem(ficha, "x:tamanho do terreno") or tem(ficha, "area_util")
    return tem(ficha, "area_util") or tem(ficha, "area_total")


@dataclass(frozen=True)
class Pergunta:
    chave: str                                   # o nome da pergunta (fica em cadastro_whats.pergunta)
    rotulo: str                                  # como aparece na lista do grupo
    texto: Callable[[dict], str]                 # o que ela escreve no privado
    preenchida: Callable[[dict], bool]
    cabe: Callable[[dict, dict], bool]           # (ficha, contexto) -> esta pergunta vale para este imóvel?
    essencial: bool = False


def _sempre(_f: dict, _c: dict) -> bool:
    return True


def _f(*familias: str) -> Callable[[dict, dict], bool]:
    return lambda ficha, _c: familia(ficha.get("tipo")) in familias


def _texto(t: str) -> Callable[[dict], str]:
    return lambda _f: t


PERGUNTAS: tuple[Pergunta, ...] = (
    Pergunta("papel", "se é o proprietário ou o corretor",
             _texto("Você é o proprietário do imóvel ou o corretor responsável por ele?"),
             lambda f: tem(f, "_papel"), lambda f, c: not c.get("papel_conhecido"), True),
    Pergunta("tipo", "tipo do imóvel",
             _texto("Qual o tipo do imóvel: apartamento, casa, casa de condomínio, sala, loja ou terreno?"),
             lambda f: tem(f, "tipo"), _sempre, True),
    Pergunta("valor", "valor", _pergunta_valor,
             lambda f: tem(f, "valor_aluguel") or tem(f, "valor_venda"), _sempre, True),
    # O CONDOMÍNIO ANTES DO RESTO: com ele cadastrado, endereço, bairro e estrutura já vêm dele
    Pergunta("condominio", "nome do condomínio", _texto("Qual o nome do condomínio?"),
             lambda f: tem(f, "condo_id") or tem(f, "condominio"),
             lambda f, _c: familia(f.get("tipo")) == "vertical" or "condom" in sem_acento(f.get("tipo")), True),
    Pergunta("condominio_confirma", "confirmar o condomínio", _pergunta_confirma,
             lambda f: tem(f, "condo_id") or bool(f.get("_condo_nao")),
             lambda f, _c: tem(f, "_condo_candidato")),
    Pergunta("c_endereco", "endereço do condomínio (condomínio novo)",
             _texto("Esse condomínio ainda não está no nosso cadastro. Qual o endereço dele (rua e número)?"),
             lambda f: tem(f, "c:logradouro"), lambda f, _c: condominio_novo(f)),
    Pergunta("c_elevador", "se o prédio tem elevador (condomínio novo)", _texto("O prédio tem elevador?"),
             lambda f: tem(f, "c:elevador"), lambda f, _c: condominio_novo(f) and familia(f.get("tipo")) == "vertical"),
    Pergunta("c_lazer", "lazer e segurança do condomínio (condomínio novo)",
             _texto("O que o condomínio tem de lazer e segurança? Por exemplo: piscina, academia, salão de festas, "
                    "portaria 24 horas."),
             lambda f: tem(f, "c:lazer") or tem(f, "c:seguranca"), lambda f, _c: condominio_novo(f)),
    Pergunta("bairro", "bairro", _texto("Em qual bairro ele fica?"),
             lambda f: tem(f, "bairro"), _sempre, True),
    Pergunta("endereco", "endereço (rua e número)", _texto("Qual o endereço do imóvel (rua e número)?"),
             lambda f: tem(f, "logradouro"), lambda f, _c: not em_condominio(f)),
    # o número do apartamento/sala/casa NUNCA é perguntado ao corretor (Tel, 20/10): só ao proprietário
    Pergunta("unidade", "unidade (torre/bloco e número)", _pergunta_unidade, _unidade_preenchida,
             lambda f, c: c.get("papel") == "proprietario" and (em_condominio(f) or familia(f.get("tipo")) == "sala")),
    Pergunta("andar", "andar (ou lances de escada)", _pergunta_andar, _andar_preenchido, _f("vertical", "sala")),
    Pergunta("area", "área (m²)", _pergunta_area, _area_preenchida, _sempre, True),
    Pergunta("quartos", "quartos e suítes", _texto("Quantos quartos, e quantos deles são suítes?"),
             lambda f: tem(f, "quartos"), _f("vertical", "casa"), True),
    Pergunta("banheiros", "banheiros", _texto("Quantos banheiros?"),
             lambda f: tem(f, "banheiros"), _f("vertical", "casa", "sala", "outro")),
    Pergunta("vagas", "vagas de garagem", _texto("Quantas vagas de garagem?"),
             lambda f: tem(f, "vagas"), _f("vertical", "casa", "sala", "outro")),
    Pergunta("mobilia", "mobília",
             _texto("Ele está mobiliado, só com modulados e ar, só climatizado ou sem nada?"),
             lambda f: tem(f, "mobilia"),
             lambda f, _c: finalidade(f) in ("locacao", "ambos", None) and familia(f.get("tipo")) in ("vertical", "casa")),
    Pergunta("taxa_condominio", "taxa de condomínio", _texto("Qual o valor da taxa de condomínio?"),
             lambda f: tem(f, "taxa_condominio"),
             lambda f, c: em_condominio(f) and not c.get("taxa_no_condominio")),
    Pergunta("caracteristicas", "o que o imóvel tem (características)",
             _texto("O que o imóvel tem de diferencial? Por exemplo: varanda, área gourmet, piscina, climatizado."),
             lambda f: tem(f, "caracteristicas"), lambda f, _c: familia(f.get("tipo")) != "terreno"),
    Pergunta("fotos", "fotos", _texto("Pode me mandar as fotos do imóvel por aqui?"),
             lambda f: bool(f.get("_fotos")), _sempre, True),
)
POR_CHAVE = {p.chave: p for p in PERGUNTAS}


def que_cabem(ficha: dict, contexto: dict | None = None) -> list[Pergunta]:
    c = contexto or {}
    return [p for p in PERGUNTAS if p.cabe(ficha, c)]


def faltam(ficha: dict, contexto: dict | None = None) -> list[str]:
    """As perguntas que ainda faltam, na ordem. A que já saiu não volta, respondida ou não (Tel: "não ficar pedindo
    2 vezes a mesma coisa"): ela fica em `_feitas`, e a que ficou vazia entra no aviso do fim (`ficou_sem`)."""
    feitas = set(ficha.get("_feitas") or ())
    return [p.chave for p in que_cabem(ficha, contexto) if not p.preenchida(ficha) and p.chave not in feitas]


def ficou_sem(ficha: dict, contexto: dict | None = None) -> list[str]:
    """Perguntou e não veio: o que a equipe completa à mão."""
    feitas = set(ficha.get("_feitas") or ())
    return [p.chave for p in que_cabem(ficha, contexto) if not p.preenchida(ficha) and p.chave in feitas]


def falta_essencial(ficha: dict, contexto: dict | None = None) -> list[str]:
    return [p.chave for p in que_cabem(ficha, contexto) if p.essencial and not p.preenchida(ficha)]


def _dinheiro(v) -> str:
    try:
        n = float(v)
    except (TypeError, ValueError):
        return str(v)
    if n >= 1_000_000:
        x = f"{n / 1_000_000:.2f}".rstrip("0").rstrip(".").replace(".", ",")
        return f"R$ {x} {'milhões' if n >= 2_000_000 else 'milhão'}"
    return "R$ " + f"{n:,.0f}".replace(",", ".")


def resumo_do_que_tem(ficha: dict) -> list[str]:
    """O que já se sabe, em linhas curtas para o grupo."""
    linhas = []
    if tem(ficha, "tipo"):
        linhas.append(ficha["tipo"])
    if tem(ficha, "condominio"):
        linhas.append(f"condomínio {ficha['condominio']}" + ("" if tem(ficha, "condo_id") else " (novo, vou cadastrar)"))
    if tem(ficha, "bairro"):
        linhas.append(f"bairro {ficha['bairro']}")
    if tem(ficha, "valor_aluguel"):
        linhas.append(f"aluguel {_dinheiro(ficha['valor_aluguel'])}")
    if tem(ficha, "valor_venda"):
        linhas.append(f"venda {_dinheiro(ficha['valor_venda'])}")
    for chave, um, varios in (("quartos", "quarto", "quartos"), ("suites", "suíte", "suítes"),
                              ("banheiros", "banheiro", "banheiros"), ("vagas", "vaga", "vagas")):
        if tem(ficha, chave):
            linhas.append(f"{ficha[chave]} {um if str(ficha[chave]) == '1' else varios}")
    if tem(ficha, "area_util"):
        linhas.append(f"{ficha['area_util']} m²")
    if tem(ficha, "andar"):
        a = str(ficha["andar"])
        linhas.append(f"{a}º andar" if a.isdigit() else a)
    if tem(ficha, "x:lances de escada"):
        linhas.append(f"{ficha['x:lances de escada']} lance(s) de escada")
    if tem(ficha, "mobilia"):
        linhas.append(str(ficha["mobilia"]))
    if tem(ficha, "taxa_condominio"):
        linhas.append(f"condomínio {_dinheiro(ficha['taxa_condominio'])}")
    if ficha.get("_fotos"):
        linhas.append(f"{ficha['_fotos']} fotos")
    return linhas


def rotulos(chaves: list[str]) -> list[str]:
    return [POR_CHAVE[c].rotulo for c in chaves if c in POR_CHAVE]


def nome_do_imovel(ficha: dict) -> str:
    """"imóvel Reserva das Praias" / "imóvel casa no Aleixo": o nome que ele reconhece."""
    if tem(ficha, "condominio"):
        return ficha["condominio"]
    tipo = (ficha.get("tipo") or "").split("/")[0].lower()
    return " ".join(x for x in (tipo, f"no {ficha['bairro']}" if tem(ficha, "bairro") else "") if x) or "que você nos passou"


def abertura(nome: str | None, ficha: dict) -> str:
    """Tel, 20/10: "Oi (NOME) estou fazendo o cadastro do seu imóvel por esse número, imóvel (NOME) pode me confirmar
    umas informações por favor?"."""
    primeiro = (nome or "").strip().split(" ")[0].capitalize()
    oi = f"Oi, {primeiro}!" if primeiro and primeiro.isalpha() else "Oi!"
    return (f"{oi} Estou fazendo o cadastro do seu imóvel por esse número, imóvel {nome_do_imovel(ficha)}. "
            "Pode me confirmar umas informações, por favor?")


def descricao_do_imovel(ficha: dict) -> str:
    """"o apartamento no Life Parque Dez" / "a casa no Aleixo": para ele saber de qual imóvel ela está falando."""
    tipo = (ficha.get("tipo") or "imóvel").split("/")[0].lower()
    artigo = "a" if tipo.startswith(("casa", "sala", "loja", "cobertura", "chácara")) else "o"
    onde = ficha.get("condominio") or ficha.get("bairro")
    return f"{artigo} {tipo}" + (f" no {onde}" if onde else "")
