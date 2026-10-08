"""O turno do proprietário: junta as mensagens do intervalo num texto só e monta o cabeçalho que o modelo lê.

É a tradução dos nós "Juntar mensagens" (código) e "AI Agent" (o texto do turno) do fluxo do n8n
`Nay - captacao proprietarios`. As frases de instrução são as MESMAS de lá, sem acento como lá: mudar uma aqui
muda o comportamento dela. Função pura: recebe as linhas que o banco devolveu e não fala com ninguém.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

# Manaus é UTC-4 o ano inteiro (sem horário de verão): não depende da base de fusos da máquina
MANAUS = timezone(timedelta(hours=-4))
NOMES_MIDIA = {"imagem": "uma imagem", "documento": "um arquivo", "video": "um video", "audio": "um audio"}
SEM_TURNO = {"texto", "reacao", "figurinha", "outro"}
PEDIU_PARAR = re.compile(
    r"\b(n[aã]o (quero|desejo|tenho interesse)|pare de|para de mandar|me tir[ea]|descadastr|sai[ar] da lista|remov[ea] meu"
    r"|n[uú]mero errado|pessoa errada|n[aã]o sou (o|a) propriet)", re.I)
DIAS = ["segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado", "domingo"]


@dataclass
class Turno:
    telefone: str
    lead_id: int | None
    nome: str
    tratamento: str
    imovel: str
    outros_nossos: str | None
    etapa: str
    situacao: str | None
    contrato_ate: str | None
    pergunta_pendente: str | None
    ficha: str | None
    qtd: int
    veio_audio: bool
    pediu_parar: bool
    texto: str
    prompt: str | None
    # o que o Tel precisa saber (foto, arquivo): o serviço decide se avisa
    aviso_ao_tel: str | None = None
    ids: list[int] = field(default_factory=list)


def _val(m: dict) -> str:
    t = m.get("texto")
    return str(t) if t and t != "null" else ""


def primeiro_nome(bruto: str | None) -> str:
    """O primeiro nome, sem o tratamento que parte do cadastro traz embutido e sem gritar em caixa alta."""
    s = re.sub(r"^(sr|sra|dr|dra|dona|exmo|exma)\.?\s+", "", str(bruto or "").strip(), flags=re.I)
    t = re.sub(r"[^A-Za-zÀ-ÿ]", "", (s.split() or [""])[0])
    if t and (t == t.upper() or t == t.lower()):
        t = t[0].upper() + t[1:].lower()
    return t


def juntar(itens: list[dict]) -> Turno | None:
    """Devolve o turno pronto, ou None quando não há o que responder (figurinha, foto repetida)."""
    itens = sorted([m for m in itens if m and m.get("id")], key=lambda m: m["id"])
    if not itens:
        return None
    texto = "\n".join(v for v in map(_val, itens) if v)
    veio_audio = any(m.get("origem") == "audio" for m in itens)
    nao_texto = []
    for m in itens:
        o = m.get("origem")
        if not _val(m) and o and o not in SEM_TURNO and o not in nao_texto:
            nao_texto.append(o)
    ficha = next((m["ficha"] for m in itens if m.get("ficha")), None)
    foto_com_legenda = bool(ficha) and any(m.get("origem") == "imagem" and _val(m) for m in itens)
    so_imagem = not texto and bool(nao_texto) and all(o == "imagem" for o in nao_texto)
    ja_seguiu = any(m.get("ja_seguiu_depois_de_foto") is True for m in itens)
    seguir_sem_foto = so_imagem and not ja_seguiu
    escreveu = any(_val(m) for m in itens)
    pendente_era_fotos = bool(re.search(r"foi sobre as fotos", ficha or ""))

    if seguir_sem_foto:
        texto = ("(ele mandou so foto" + ("s" if len(itens) > 1 else "") + " do imovel, sem escrever nada. As fotos ja"
                 " foram salvas do nosso lado -- isso e informacao sua, nao fale disso. "
                 + ('Era a pergunta das fotos: diga so "Recebi, obrigada!", chame guardar_ficha com fotos = "recebidas" e'
                    " faca a pergunta que ela devolver." if ficha and pendente_era_fotos
                    else "NAO chame guardar_ficha agora e nao fale das fotos: refaca, em uma linha, a ultima pergunta que voce"
                    " fez (a do aviso da ficha), que ficou sem resposta." if ficha
                    else "Nao fale das fotos: continue o atendimento de onde parou, refazendo em uma linha a ultima pergunta"
                    " que ficou sem resposta (ou a proxima do roteiro).")
                 + " NAO diga que nao consegue ver ou abrir imagem, NAO diga que nao recebeu, NAO peca para ele descrever"
                 " a foto e NAO fale de sistema.)")
    if not texto and nao_texto and not so_imagem:
        texto = ("(ele mandou " + " e ".join(NOMES_MIDIA.get(o, o) for o in nao_texto)
                 + '. isso chegou bem e ja foi visto do nosso lado. agradeca em uma linha -- "Recebi, obrigada!" -- e '
                 + ('chame guardar_ficha com fotos = "recebidas" (a ficha do imovel esta aberta) e siga a instrucao que ela'
                    " devolver." if ficha and "imagem" in nao_texto else "siga o roteiro de onde parou.")
                 + " NAO diga que nao consegue abrir, NAO diga que nao recebeu, NAO peca"
                 " para ele escrever o que esta na foto e NAO fale de sistema nenhum.)")
    if foto_com_legenda:
        texto += '\n(junto veio foto do imovel, ja guardada na ficha: chame guardar_ficha com fotos = "recebidas" junto com o resto.)'
    if not texto and not so_imagem:
        return None

    p = itens[0]
    nome = primeiro_nome(p.get("nome"))
    aviso = None
    if nao_texto:
        o_que = " e ".join(NOMES_MIDIA.get(o, o) for o in nao_texto)
        aviso = (f"Captacao: {nome or 'o proprietario'} ({p.get('telefone')}) mandou {o_que}, que a Nay nao abre."
                 + ("\n\nEla nao comentou a foto e seguiu com as perguntas do cadastro." if seguir_sem_foto
                    else "\n\nEla nao respondeu: ja tinha seguido o atendimento depois das fotos anteriores." if so_imagem
                    else "\n\nEla seguiu o atendimento sem comentar a foto." if escreveu
                    else "\n\nEla agradeceu e seguiu o roteiro, sem dizer que nao conseguia ver."))
    if so_imagem and not seguir_sem_foto:
        # nada a responder, mas o Tel ainda fica sabendo da foto
        return Turno(telefone=p.get("telefone") or "", lead_id=p.get("lead_id"), nome=nome, tratamento="", imovel="",
                     outros_nossos=None, etapa="", situacao=None, contrato_ate=None, pergunta_pendente=None, ficha=ficha,
                     qtd=len(itens), veio_audio=False, pediu_parar=False, texto="", prompt=None, aviso_ao_tel=aviso,
                     ids=[m["id"] for m in itens])
    return Turno(
        telefone=p.get("telefone") or "", lead_id=p.get("lead_id"), nome=nome, tratamento=p.get("tratamento") or "",
        imovel=p.get("imovel_desc") or p.get("condominio") or p.get("bairro") or "",
        outros_nossos=p.get("outros_nossos") or None, etapa=p.get("etapa") or "aguardando_situacao",
        situacao=p.get("situacao") or None, contrato_ate=p.get("contrato_ate") or None,
        pergunta_pendente=p.get("pergunta_pendente") or None, ficha=ficha, qtd=len(itens), veio_audio=veio_audio,
        pediu_parar=bool(PEDIU_PARAR.search(texto)), texto=texto, prompt=p.get("prompt") or None, aviso_ao_tel=aviso,
        ids=[m["id"] for m in itens])


def _agora_em_manaus(agora: datetime) -> str:
    a = agora.astimezone(MANAUS)
    return f"{DIAS[a.weekday()]} {a:%d/%m/%Y %H:%M}"


def cabecalho(t: Turno, agora: datetime) -> str:
    """O texto do turno, igual ao do nó "AI Agent" (campo `text`)."""
    partes = [
        "(informação de sistema, não repita isso ao proprietário) agora em Manaus é " + _agora_em_manaus(agora) + ".",
        "o proprietário é " + (t.tratamento or "(tratamento desconhecido -- NAO escreva Sr. nem Sra., chame so pelo primeiro nome)")
        + " " + (t.nome or "(nome não cadastrado -- fale sem vocativo, não invente)") + ".",
        "o imóvel dele no nosso cadastro é: "
        + (t.imovel or '(não cadastrado -- se precisar citar, fale "o seu imóvel" sem detalhar)') + ".",
        f"a etapa atual da conversa é: {t.etapa}.",
    ]
    if t.outros_nossos:
        partes.append("ATENÇÃO: além do imóvel acima, este proprietário JÁ TEM estes outros imóveis conosco: " + t.outros_nossos
                      + ". Se ele citar um destes como se fosse novidade, NÃO registre como imóvel novo -- diga que já está no"
                      " nosso cadastro e siga. Só é imóvel novo o que NÃO estiver nesta lista.")
    if t.situacao:
        partes.append(f"a situação já registrada é: {t.situacao}. não pergunte de novo.")
    if t.contrato_ate:
        partes.append(f"o prazo já registrado é: {t.contrato_ate}.")
    if t.pergunta_pendente:
        partes.append(f"a pergunta que ficou aberta com ele foi: {t.pergunta_pendente}.")
    if t.qtd > 1:
        partes.append(f"ATENÇÃO: ele mandou {t.qtd} mensagens neste intervalo, e elas vieram JUNTAS abaixo, uma por linha."
                      " Responda o conjunto, não só a última.")
    if t.veio_audio:
        partes.append("ele respondeu por ÁUDIO e o texto abaixo é a transcrição. Antes de gravar qualquer dado, repita em uma"
                      " linha o que entendeu e peça a confirmação dele.")
    if t.pediu_parar:
        partes.append("ATENÇÃO: o texto dele tem sinal de que ele NÃO QUER receber mensagem, ou de que o número está errado."
                      " Peça desculpa em uma linha, diga que vai remover, chame encerrar_conversa com motivo opt_out e NÃO"
                      " faça mais nenhuma pergunta do roteiro.")
    if t.ficha:
        partes.append(t.ficha)
    partes.append("mensagem do proprietário: " + t.texto)
    return " ".join(partes)
