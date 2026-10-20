"""A ficha nos três formatos: o que o modelo devolve, o que o serviço guarda e o que a API do site recebe.

O modelo devolve sempre o MESMO objeto (FICHA_SCHEMA), tanto ao ler o texto que o Tel encaminhou quanto ao ler a
resposta do corretor: o que ele não sabe vem null. `do_modelo` traduz para as chaves da ficha (campos.py) e
`para_o_site` monta o corpo do POST/PUT /admin/api/imoveis.
"""
from __future__ import annotations

from cadastro.campos import MOBILIA, TIPOS, tipo_canonico


def _n(tipo: str) -> dict:
    return {"type": [tipo, "null"]}


def _enum(valores) -> dict:
    return {"type": ["string", "null"], "enum": [*valores, None]}


def _lista() -> dict:
    return {"type": "array", "items": {"type": "string"}}


CAMPOS_DO_MODELO = {
    "tipo": _enum(TIPOS),
    "finalidade": _enum(("locacao", "venda", "ambos")),
    "valor_aluguel": _n("number"), "valor_venda": _n("number"), "taxa_condominio": _n("number"), "iptu": _n("number"),
    "condominio": _n("string"),
    "bairro": _n("string"), "logradouro": _n("string"), "numero": _n("string"), "complemento": _n("string"),
    "torre": _n("string"), "bloco": _n("string"), "unidade": _n("string"), "casa": _n("string"), "lote": _n("string"),
    "andar": _n("string"), "lances_escada": _n("integer"),
    "area_util": _n("number"), "area_total": _n("number"), "tamanho_terreno": _n("number"),
    "quartos": _n("integer"), "suites": _n("integer"), "banheiros": _n("integer"), "vagas": _n("integer"),
    "vagas_cobertas": _n("integer"),
    "mobilia": _enum(MOBILIA),
    "caracteristicas": _lista(),
    "aceita_financiamento": _enum(("sim", "nao")),
    "permuta": _n("string"),
    "condominio_logradouro": _n("string"), "condominio_numero": _n("string"),
    "condominio_elevador": _enum(("sim", "nao")),
    "condominio_lazer": _lista(), "condominio_seguranca": _lista(),
    "papel": _enum(("proprietario", "corretor")),
    "contato_nome": _n("string"),
}


def _objeto(extra: dict) -> dict:
    props = {**CAMPOS_DO_MODELO, **extra}
    return {"type": "object", "properties": props, "required": list(props), "additionalProperties": False}


# ao ler a leva do grupo
SCHEMA_LEVA = _objeto({
    "e_imovel": {"type": "boolean"},
    "contato_telefone": _n("string"),
    "descricao": _n("string"),
})
# ao ler a resposta do corretor a UMA pergunta
SCHEMA_RESPOSTA = _objeto({
    "respondeu": {"type": "boolean"},
    "nao_sabe": {"type": "boolean"},
    "fora_do_assunto": {"type": "boolean"},
})

# do nome no modelo para a chave da ficha
PARA_A_FICHA = {
    "torre": "p:torre", "bloco": "p:bloco", "unidade": "p:unidade", "casa": "p:casa", "lote": "p:lote",
    "tamanho_terreno": "x:tamanho do terreno", "lances_escada": "x:lances de escada", "aceita_financiamento": "x:aceita financiamento",
    "permuta": "x:permuta", "condominio_logradouro": "c:logradouro", "condominio_numero": "c:numero",
    "condominio_elevador": "c:elevador", "condominio_lazer": "c:lazer", "condominio_seguranca": "c:seguranca",
    "papel": "_papel", "finalidade": "_finalidade", "contato_nome": "_contato_nome",
}
FORA_DA_FICHA = {"e_imovel", "contato_telefone", "respondeu", "nao_sabe", "fora_do_assunto"}


def do_modelo(saida: dict) -> dict:
    """Só o que veio preenchido, nas chaves da ficha."""
    ficha = {}
    for k, v in (saida or {}).items():
        if k in FORA_DA_FICHA or v in (None, "", []):
            continue
        if k == "tipo":
            v = tipo_canonico(v) or v
        if isinstance(v, float) and v.is_integer() and k in ("quartos", "suites", "banheiros", "vagas", "vagas_cobertas"):
            v = int(v)
        ficha[PARA_A_FICHA.get(k, k)] = v
    return ficha


def juntar(ficha: dict, novo: dict) -> dict:
    """O que veio agora completa a ficha. Lista soma (características); o resto, o novo vale (é a correção dele)."""
    saida = dict(ficha)
    for k, v in novo.items():
        if isinstance(v, list) and isinstance(saida.get(k), list):
            saida[k] = list(dict.fromkeys([*saida[k], *v]))
        else:
            saida[k] = v
    return saida


COLUNAS = ("tipo", "bairro", "logradouro", "numero", "complemento", "area_util", "area_total", "quartos", "suites",
           "banheiros", "vagas", "vagas_cobertas", "andar", "valor_venda", "valor_aluguel", "taxa_condominio", "iptu",
           "mobilia", "descricao", "caracteristicas", "condo_id")


def para_o_site(ficha: dict) -> dict:
    """O corpo do POST/PUT do site: colunas, "extras" (x:), "privado" (p:). O proprietário entra à parte."""
    corpo: dict = {k: ficha[k] for k in COLUNAS if ficha.get(k) not in (None, "", [])}
    extras = {k[2:]: ficha[k] for k in ficha if k.startswith("x:") and ficha[k] not in (None, "", [])}
    privado = {k[2:]: ficha[k] for k in ficha if k.startswith("p:") and ficha[k] not in (None, "", [])}
    if extras:
        corpo["extras"] = {k: ("Sim" if v == "sim" else "Não" if v == "nao" else v) for k, v in extras.items()}
    if privado:
        corpo["privado"] = privado
    return corpo


def condominio_para_o_site(ficha: dict) -> dict:
    """O corpo do POST /admin/api/imoveis/condominios para o condomínio novo."""
    corpo = {"nome": ficha.get("condominio"), "bairro": ficha.get("bairro"),
             "tipo": "apartamentos" if "condom" not in (ficha.get("tipo") or "").lower() else "casas_lotes",
             "logradouro": ficha.get("c:logradouro"), "numero": ficha.get("c:numero"),
             "cidade": "Manaus", "estado": "AM"}
    if ficha.get("c:elevador") in ("sim", "nao"):
        # como a tela do condomínio escreve (condominio-cadastro.js)
        corpo["elevador"] = "Sim, possui elevador" if ficha["c:elevador"] == "sim" else "Não possui elevador"
    if ficha.get("c:lazer"):
        corpo["lazer"] = list(ficha["c:lazer"])
    if ficha.get("c:seguranca"):
        corpo["seguranca"] = list(ficha["c:seguranca"])
    return {k: v for k, v in corpo.items() if v not in (None, "", [])}
