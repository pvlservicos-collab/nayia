"""
Prova o colhedor do grupo Alto Padrão contra as frases REAIS do corpus.

TODAS as frases deste arquivo foram lidas da tabela `mensagens` em 23/09/2026.
Nenhuma é inventada -- é o que separa um detector medido de um detector
desejado, e a regra do projeto é medir contra as mensagens reais.

O QUE IMPORTA PROVAR:

  * quem PEDE é reconhecido, nas seis formas diferentes que apareceram em
    quinze minutos;
  * quem FALA DE GRUPO sem pedir NÃO é -- são quatro formas medidas, e cada
    uma renderia uma pergunta fora de hora a um corretor;
  * o comando do Tel nunca entra. Ele escreveu 14 "Posta no grupo anunciar
    easy NNNN" só em 23/09, e o `@lid` faz o telefone dele não bastar;
  * "Portal do Rio Negro" é CONDOMÍNIO. Portal se lê por nome, nunca pela
    palavra;
  * e-mail não é Instagram. É a forma de "@" que mais aparece no corpus;
  * uma pergunta por pessoa, para sempre;
  * a resposta só é lida de quem JÁ foi perguntado -- senão o "@" de uma
    conversa qualquer vira o Instagram de alguém;
  * simulação por padrão (regra 4): sem `--escrever`, nada é gravado e nada
    é enviado.

Uso:
    .venv/bin/python teste_filtrar_alto_padrao.py
"""
import datetime
from zoneinfo import ZoneInfo

import filtrar_alto_padrao as f

FUSO = ZoneInfo("America/Manaus")
falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = obtido == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}, veio {obtido!r}")


print("--- QUEM PEDE é reconhecido (frases reais de 23/09, 20:35-20:41) ---")
PEDEM = [
    "Ou.. \n\nSobre seu grupo Alto-Padrão.",                      # Marcos
    "Sobre o grupo",                                              # Nora
    "Boa Noite, Nay. Tudo bem ? Me chamo:Heber . Creci : 6669 PF "
    "e Cnai 58944 . Gostaria de participar do grupo",             # Heber
    "TENHO INTERESSE NESSES IMÓVEIS ALTO PADRÃO OK",              # Izaías
    "Eu trabalho amiga de alto padrão",                           # Ana Cortêz
    "📣🔥 QUEM TRABALHA COM IMÓVEL ALTO PADRÃO ME PROCURE, VOU "
    "FAZER UM GRUPO PEQUENO SÓ PARA QUEM TRABALHA COM ALTO PADRÃO",  # Ane
    "Ainda não estou no grupo, como faço pra entrar?",            # Francimary
]
for frase in PEDEM:
    checar(repr(frase[:46]), f.pede_alto_padrao(frase), True)

print()
print("--- QUEM FALA DE GRUPO e NÃO está pedindo (4 falsos positivos medidos) ---")
NAO_PEDEM = [
    "Esse tá no grupo da EASY?",                                  # Leonan
    "Os imóveis que você posta nos grupos podem ser anunciados?",  # Alessandra
    "vou anunciar seus imóveis do grupo então pode ser ?",         # Rachel
    "QUANDO PUDER ME MANDA AQUI NO GRUPO AS INFORMAÇÕES OK",       # Izaías
    "Coloca no grupo",                                            # João Luiz
]
for frase in NAO_PEDEM:
    checar(repr(frase[:46]), f.pede_alto_padrao(frase), False)

print()
print("--- o COMANDO DO TEL nunca entra (14 em 23/09) ---")
# O telefone dele não basta como parede: ele também chega pelo `@lid`.
for frase in ["Posta no grupo anunciar easy 3227",
              "Nay posta no grupo anunciar easy lista de apartamentos",
              "Posta no grupo imóveis para anunciar easy 5746",
              "Nay dispara lista de apartamento para locação nos grupos",
              "envia 92 99462-9241 codigo 150"]:
    checar(repr(frase[:46]), f.pede_alto_padrao(frase), False)

print()
print("--- texto vazio não é pedido ---")
checar("vazio", f.pede_alto_padrao(""), False)
checar("None", f.pede_alto_padrao(None), False)
checar("só espaço", f.pede_alto_padrao("   \n "), False)

print()
print("--- PORTAL DO RIO NEGRO é condomínio, não portal (5 de 15 medidas) ---")
checar("Portal do rio negro", f.achar_portais("Portal do rio negro"), [])
checar("📍 Portal do Rio Negro | • Bairro: Compensa",
       f.achar_portais("📍 Portal do Rio Negro\n• Bairro: Compensa"), [])
checar("Tem Portal da Cidade em Aleixo para venda",
       f.achar_portais("Tem Portal da Cidade em Aleixo para venda"), [])
checar("'uso portais' sem nome não afirma portal nenhum",
       f.achar_portais("uso portais sim"), [])

print()
print("--- mas o portal citado pelo NOME é lido ---")
checar("Eu anunciei no olx", f.achar_portais("Eu  anunciei no olx"), ["OLX"])
checar("link da OLX",
       f.achar_portais("https://am.olx.com.br/regiao-de-manaus/imoveis/casa"),
       ["OLX"])
checar("vivareal e zap imóveis",
       f.achar_portais("trabalho com VivaReal e Zap Imóveis"),
       ["VivaReal", "ZAP"])
checar("quinto andar", f.achar_portais("uso o Quinto Andar"), ["QuintoAndar"])
checar("chaves na mão", f.achar_portais("chaves na mao tambem"),
       ["Chaves na Mão"])
checar("dois de uma vez, na ordem da lista",
       f.achar_portais("olx, imovelweb e chaves na mão"),
       ["OLX", "ImovelWeb", "Chaves na Mão"])

print()
print('--- "esse zap tbm é meu" é WHATSAPP, não o portal ZAP ---')
# Frase real do Imob.manaus, 08/09. Sem a guarda, ele entraria como portal.
checar("esse zap tbm é meu",
       f.achar_portais("Ten algum ponto de referência? Aqui é o Leonardo "
                       "esse zap tbm é meu"), [])

print()
print("--- E-MAIL não é Instagram (a forma de @ que mais aparece) ---")
for email in ["imoveispinho28@gmail.com",
              "marluporfirio.imoveis@gmail.com",
              "Com cópia para o Sr. Marcelo e pra mim: bmb.marcelo@gmail.com",
              "walterjunior607@gmail.com"]:
    checar(repr(email[:40]), f.achar_instagram(email), None)

print()
print("--- mas o Instagram de verdade é lido ---")
checar("@ solto", f.achar_instagram("meu @erick.imoveis"), "erick.imoveis")
checar("link do perfil",
       f.achar_instagram("https://www.instagram.com/nara.corretora/"),
       "nara.corretora")
# Link de POST não carrega o perfil. É o único link de Instagram do corpus
# (Nara, 12/09) -- e antes da guarda ele devolvia "com" como se fosse o @ dela.
checar("link de post não inventa perfil",
       f.achar_instagram("https://www.instagram.com/p/DdMIZgSkb08/?img_index=8"),
       None)
checar("'meu insta é X'", f.achar_instagram("meu insta é joao.imoveis"),
       "joao.imoveis")
checar("'instagram: X'", f.achar_instagram("instagram: casa_manaus"),
       "casa_manaus")
checar("e-mail junto do @ não confunde",
       f.achar_instagram("erick@gmail.com e meu @erickcorretor"),
       "erickcorretor")
checar("'Como está no Instagram amanhã tem pessoa ver' não é um @",
       f.achar_instagram("Como está no Instagram amanhã tem pessoa ver"), None)

print()
print("--- a saudação segue a hora de Manaus ---")
checar("09h", f.saudacao(datetime.datetime(2026, 9, 23, 9, tzinfo=FUSO)),
       "bom dia")
checar("14h", f.saudacao(datetime.datetime(2026, 9, 23, 14, tzinfo=FUSO)),
       "boa tarde")
checar("20h", f.saudacao(datetime.datetime(2026, 9, 23, 20, tzinfo=FUSO)),
       "boa noite")
# O servidor é UTC. 23h em UTC é 19h em Manaus -- ainda "boa noite", mas 01h
# UTC é 21h de ONTEM em Manaus, e sem o fuso viraria "bom dia".
checar("01h UTC ainda é boa noite em Manaus",
       f.saudacao(datetime.datetime(2026, 9, 24, 1,
                                    tzinfo=ZoneInfo("UTC"))), "boa noite")

print()
print("--- a pergunta é a do Tel, palavra por palavra ---")
msg = f.montar_pergunta(datetime.datetime(2026, 9, 23, 20, tzinfo=FUSO),
                        "Marcos Moraes")
checar("cumprimenta pelo primeiro nome", msg.startswith("oi Marcos, boa noite"),
       True)
checar("pergunta instagram ou portais", "instagram anunciando alto padrão "
       "ou por portais imobiliários" in msg, True)
checar("pergunta quais portais", "quais seriam?" in msg, True)
checar("pede o instagram", "pode me enviar caso trabalhe por lá" in msg, True)
checar("sem markdown (a regra da Nay)", "*" in msg or "#" in msg, False)
checar("sem nome ainda cumprimenta",
       f.montar_pergunta(datetime.datetime(2026, 9, 23, 9, tzinfo=FUSO))
       .startswith("oi, bom dia"), True)


# ---------------------------------------------------------------- o banco fake
class CursorFake:
    def __init__(self, conn):
        self.conn = conn
        self.linhas = []

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        s = " ".join(sql.split())
        self.linhas = []
        # A ORDEM IMPORTA: "FROM corretor_alto_padrao" casa antes de
        # "UPDATE corretor_alto_padrao" se o teste for escrito ao contrário --
        # foi esse exato erro que deixou o DELETE do detector de visitas cair
        # no ramo de leitura e passar sem exercitar parede nenhuma.
        if s.startswith("INSERT INTO corretor_alto_padrao"):
            tel = params[0]
            self.conn.fichas.setdefault(tel, {
                "telefone": tel, "nome": params[1], "pediu_texto": params[2],
                "perguntado_em": None, "instagram": None, "portais": None,
                "respondido_em": None})
        elif s.startswith("UPDATE corretor_alto_padrao SET perguntado_em"):
            self.conn.fichas[params[0]]["perguntado_em"] = "agora"
        elif s.startswith("UPDATE corretor_alto_padrao SET instagram"):
            fi = self.conn.fichas[params[4]]
            fi["instagram"] = fi["instagram"] or params[0]
            fi["portais"] = fi["portais"] or params[2]
            fi["respondido_em"] = fi["respondido_em"] or "agora"
        elif s.startswith("INSERT INTO config"):
            self.conn.carimbo = params[0]
        elif "SELECT telefone, nome FROM corretor_alto_padrao" in s:
            self.linhas = [x for x in self.conn.fichas.values()
                           if x["perguntado_em"] is None]
        elif "SELECT telefone, perguntado_em FROM corretor_alto_padrao" in s:
            self.linhas = list(self.conn.fichas.values())
        elif "FROM mensagens m" in s:
            self.linhas = list(self.conn.mensagens)
        elif "SELECT valor FROM config" in s:
            self.linhas = ([{"valor": self.conn.carimbo}]
                           if self.conn.carimbo else [])
        elif "coalesce(max(id),0)" in s:
            self.linhas = [{"id": max((m["id"] for m in self.conn.mensagens),
                                      default=0)}]

    def fetchall(self):
        return self.linhas

    def fetchone(self):
        return self.linhas[0] if self.linhas else None


class ConnFake:
    def __init__(self, mensagens, fichas=None):
        self.mensagens = mensagens
        self.fichas = fichas or {}
        self.carimbo = None

    def cursor(self):
        return CursorFake(self)

    def commit(self):
        pass

    def close(self):
        pass


def msg(id, tel, nome, texto):
    return {"id": id, "telefone": tel, "nome": nome, "texto": texto,
            "criada_em": None}


AGORA = datetime.datetime(2026, 9, 23, 20, 45, tzinfo=FUSO)


TEL = "559294717316"


def rodar(mensagens, fichas=None, escrever=True, carimbo="0"):
    conn = ConnFake(mensagens, fichas)
    conn.carimbo = carimbo
    enviadas = []
    feito = f.filtrar(conexao=conn, agora=AGORA, escrever=escrever,
                      tel_whatsapp=TEL,
                      enviar=lambda d, t: enviadas.append((d, t)))
    return conn, feito, enviadas


print()
print("--- ponta a ponta: o Marcos pede, é perguntado, e responde ---")
conn, feito, enviadas = rodar([
    msg(1, "5592984787190", "Marcos Moraes", "Ou..\n\nSobre seu grupo Alto-Padrão."),
])
checar("abriu a ficha", len(conn.fichas), 1)
checar("mandou UMA pergunta", len(enviadas), 1)
checar("para o número dele", enviadas[0][0], "5592984787190")
checar("marcou que perguntou",
       conn.fichas["5592984787190"]["perguntado_em"], "agora")
checar("guardou a frase dele",
       "Alto-Padrão" in conn.fichas["5592984787190"]["pediu_texto"], True)

print()
print("--- a resposta dele é lida e guardada ---")
conn, feito, enviadas = rodar(
    [msg(2, "5592984787190", "Marcos Moraes",
         "trabalho com instagram sim, @marcosmoraes.imoveis, e uso a OLX")],
    fichas={"5592984787190": {"telefone": "5592984787190", "nome": "Marcos",
                              "perguntado_em": "antes", "instagram": None,
                              "portais": None, "respondido_em": None}})
# Só o que foi PARA ELE conta como pergunta -- o aviso ao Tel também passa
# pelo mesmo `enviar`, e contá-lo esconderia uma repergunta de verdade.
checar("não pergunta de novo",
       len([t for d, t in enviadas if d != TEL]), 0)
checar("guardou o instagram",
       conn.fichas["5592984787190"]["instagram"], "marcosmoraes.imoveis")
checar("guardou o portal", conn.fichas["5592984787190"]["portais"], "OLX")
checar("marcou respondido",
       conn.fichas["5592984787190"]["respondido_em"], "agora")

print()
print("--- UMA PERGUNTA POR PESSOA, para sempre ---")
# Ele volta a falar do grupo. Perguntar de novo vira interrogatório.
conn, feito, enviadas = rodar(
    [msg(3, "5592984787190", "Marcos", "e sobre o grupo, quando entro?")],
    fichas={"5592984787190": {"telefone": "5592984787190", "nome": "Marcos",
                              "perguntado_em": "antes", "instagram": None,
                              "portais": None, "respondido_em": None}})
checar("não repergunta", len(enviadas), 0)

print()
print("--- o @ de quem NÃO foi perguntado não vira Instagram de ninguém ---")
# Sem esta parede, qualquer "@" de qualquer conversa entraria numa ficha.
conn, feito, enviadas = rodar(
    [msg(4, "559299999999", "Outro", "manda pro @joaozinho por favor")])
checar("nenhuma ficha aberta", len(conn.fichas), 0)
checar("nada enviado", len(enviadas), 0)
checar("nenhuma resposta colhida",
       [x for x in feito if x["o_que"] == "resposta"], [])

print()
print("--- quem foi perguntado mas responde SEM dado não é marcado ---")
conn, feito, enviadas = rodar(
    [msg(5, "5592984787190", "Marcos", "vou ver aqui e te falo")],
    fichas={"5592984787190": {"telefone": "5592984787190", "nome": "Marcos",
                              "perguntado_em": "antes", "instagram": None,
                              "portais": None, "respondido_em": None}})
checar("segue sem resposta",
       conn.fichas["5592984787190"]["respondido_em"], None)

print()
print("--- SIMULAÇÃO não grava e não manda (regra 4) ---")
conn, feito, enviadas = rodar(
    [msg(6, "5592984787190", "Marcos", "Sobre seu grupo Alto-Padrão.")],
    escrever=False)
checar("não gravou ficha", len(conn.fichas), 0)
# O carimbo NÃO avança: ficou no "0" com que o cenário começou. Se avançasse,
# a rodada de verdade pularia essas mensagens sem nunca ter perguntado nada.
checar("não avançou a marca d'água", conn.carimbo, "0")
checar("mas mostra o que faria",
       [x["o_que"] for x in feito], ["ficha"])

print()
print("--- a marca d'água avança até a última mensagem lida ---")
conn, feito, enviadas = rodar([
    msg(10, "5592984787190", "Marcos", "Sobre seu grupo Alto-Padrão."),
    msg(11, "559299999999", "Outro", "bom dia"),
    msg(12, "559288888888", "Terceiro", "quanto custa o 5718?"),
])
checar("carimbo na última", conn.carimbo, "12")
checar("só o Marcos virou ficha", list(conn.fichas), ["5592984787190"])

print()
print("--- as seis pessoas de 23/09 entram, e o Tel não ---")
conn, feito, enviadas = rodar([
    msg(20, "5592984787190", "Marcos Moraes", "Sobre seu grupo Alto-Padrão."),
    msg(21, "559298619286", "Heber Gomes", "Gostaria de participar do grupo"),
    msg(22, "559293855726", "Nora Maria", "Sobre o grupo"),
    msg(23, "559299406646", "Ane Cavalcante",
        "QUEM TRABALHA COM IMÓVEL ALTO PADRÃO ME PROCURE"),
    msg(24, "559291988585", "Izaías", "TENHO INTERESSE NESSES IMÓVEIS ALTO PADRÃO OK"),
    msg(25, "559293965797", "Ana Cortêz", "Eu trabalho amiga de alto padrão"),
    msg(26, "559294717316", "Tel Sobreira", "Posta no grupo anunciar easy 3227"),
])
checar("seis fichas", len(conn.fichas), 6)
checar("seis perguntas", len(enviadas), 6)
checar("o Tel ficou de fora", "559294717316" in conn.fichas, False)

print()
print("--- o Tel RECEBE o Instagram, senão a tabela não serve ---")
# "quero avaliar o instagram deles": avaliar exige ver, e ele não abre o banco.
conn, feito, enviadas = rodar(
    [msg(40, "5592984787190", "Marcos Moraes",
         "sim, @marcosmoraes.imoveis e uso OLX e VivaReal")],
    fichas={"5592984787190": {"telefone": "5592984787190", "nome": "Marcos",
                              "perguntado_em": "antes", "instagram": None,
                              "portais": None, "respondido_em": None}})
avisos = [t for d, t in enviadas if d == TEL]
checar("um aviso ao Tel", len(avisos), 1)
checar("com o nome e o telefone bonito",
       "Marcos Moraes ((92) 98478-7190)" in avisos[0], True)
checar("com o link do perfil",
       "instagram.com/marcosmoraes.imoveis" in avisos[0], True)
checar("e com os portais", "OLX, VivaReal" in avisos[0], True)

print()
print("--- quem não mandou Instagram é dito, não escondido ---")
conn, feito, enviadas = rodar(
    [msg(41, "5592984787190", "Marcos", "eu uso só a OLX")],
    fichas={"5592984787190": {"telefone": "5592984787190", "nome": "Marcos",
                              "perguntado_em": "antes", "instagram": None,
                              "portais": None, "respondido_em": None}})
avisos = [t for d, t in enviadas if d == TEL]
checar("o Tel é avisado assim mesmo", len(avisos), 1)
checar("dizendo que não mandou", "instagram: não mandou" in avisos[0], True)

print()
print("--- o aviso sai UMA VEZ SÓ por pessoa ---")
# Ele repete o @ na mensagem seguinte. Sem a guarda, o Tel recebe de novo.
conn, feito, enviadas = rodar(
    [msg(42, "5592984787190", "Marcos", "@marcosmoraes.imoveis"),
     msg(43, "5592984787190", "Marcos", "esse mesmo, @marcosmoraes.imoveis")],
    fichas={"5592984787190": {"telefone": "5592984787190", "nome": "Marcos",
                              "perguntado_em": "antes", "instagram": None,
                              "portais": None, "respondido_em": None}})
checar("um aviso, não dois", len([t for d, t in enviadas if d == TEL]), 1)

print()
print("--- a PRIMEIRA RODADA não varre o histórico ---")
# Sem esta parede o carimbo nasce em zero, o cron lê as 19 mil mensagens do
# banco e manda as três perguntas para todo mundo que já citou "alto padrão"
# desde agosto. É a lição que o `detectar_visitas` já traz escrita.
conn, feito, enviadas = rodar([
    msg(30, "5592984787190", "Marcos", "Sobre seu grupo Alto-Padrão."),
    msg(31, "559298619286", "Heber", "Gostaria de participar do grupo"),
], carimbo=None)
checar("nenhuma pergunta sai", len(enviadas), 0)
checar("nenhuma ficha aberta", len(conn.fichas), 0)
checar("o carimbo nasce no fim da fila", conn.carimbo, "31")
checar("e diz o que fez", [x["o_que"] for x in feito], ["nasceu"])

print()
print("--- mas o --desde olha para trás, de propósito ---")
conn, feito, enviadas = rodar([
    msg(30, "5592984787190", "Marcos", "Sobre seu grupo Alto-Padrão."),
], carimbo=None)
checar("sem --desde, nada", len(enviadas), 0)
conn = ConnFake([msg(30, "5592984787190", "Marcos",
                     "Sobre seu grupo Alto-Padrão.")])
conn.carimbo = None
enviadas = []
f.filtrar(conexao=conn, agora=AGORA, escrever=True, desde=29,
          enviar=lambda d, t: enviadas.append((d, t)))
checar("com --desde 29, o Marcos entra", len(conn.fichas), 1)
checar("e recebe a pergunta", len(enviadas), 1)

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DO FILTRO ALTO PADRÃO PASSARAM")
