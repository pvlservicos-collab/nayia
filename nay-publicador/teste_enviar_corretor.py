"""
Testa o comando de ENVIO PRIVADO: "Nay manda o 5750 pro Sergio".

POR QUE ELE EXISTE: até 31/08 não havia caminho nenhum para mandar imóvel
a um corretor sem ele escrever primeiro. O Tel pediu três vezes que a Nay
mandasse três imóveis ao Gustavo; nas três eu dei um comando `RESPOSTA`
que só manda texto, e ela prometeu o que o mecanismo não fazia.

O QUE IMPORTA PROVAR:
  * a preposição separa isto de `posta`, que vai para os 14 GRUPOS. Errar
    aqui manda para 14 grupos o que era para uma pessoa, e não tem desfazer;
  * cauda de grupo ("pro grupo de anunciar da easy") continua caindo no
    caminho antigo -- foi a regressão que o teste pegou antes de subir;
  * verbo de grupo com destinatário pessoal RECUSA e explica;
  * horário no meio recusa, em vez de virar vaga.

Uso:
    .venv/bin/python teste_enviar_corretor.py
"""
from interpretar_comando import interpretar_comando as ic

falhas = 0


def checar(texto, esperado, detalhe=""):
    global falhas
    obtido = ic(texto).get("acao")
    ok = obtido == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {texto[:52]:54s} -> {obtido}")
    if not ok:
        print(f"         esperava {esperado}. {detalhe}")


print("--- envio privado reconhecido ---")
for t in [
    "Nay manda o 5750 pro Sergio",
    "Nay envia o 5750 pro Sergio",
    "envia o 5750 pra Samira",
    "manda o 5750 p/ o Gustavo",
    "Nay repassa o 2943 pro corretor Leonan",
    "encaminha o 5611 pro Moacy",
    "Nay mnda os acquarele p/ o sergio",
    "Nay envia todos os acquarelle para locacao para o corretor Sergio",
    "Nay manda o 5750 pro 92 99999-8888",
]:
    checar(t, "enviar_para_corretor")

from interpretar_comando import interpretar_comando as _ic0

print()
print("--- TELEFONE NA FRENTE, sem preposição (Tel, 23/09) ---")
# Ele escreveu "envia (92) 98478-7190 o 3210", o ENVIO_RE não casou -- ele
# EXIGE "para/pra/pro" -- e a frase foi ao AGENTE, que escalou de volta:
# "perguntou uma coisa que eu ainda não sei responder". O imóvel não saiu.
#
# A preposição NÃO pode ser afrouxada no ENVIO_RE: é ela que separa o envio
# privado do `posta`, que vai para os 19 grupos. Por isso esta forma tem regex
# própria, e é estreita: só vale com TELEFONE (10 ou 11 dígitos), que nenhum
# código de imóvel tem.
for t in [
    "envia (92) 98478-7190 o 3210",
    "envia 92 98478-7190 o 3210",
    "manda (92) 98478-7190 o 3210",
    "Nay envia (92) 98478-7190 o 3210 e o 3211",
    "envia 92984787190 3210",
]:
    checar(t, "enviar_para_corretor")

print()
print('--- COM A PALAVRA "CODIGO", e ate 2 digitos (Tel, 23/09) ---')
# Ele escreveu "envia 92 99462-9241  codigo 150" as 19:58 e a frase NAO casou:
# a regex de 23/09 so aceitava artigo ("o 3210"), nunca a palavra. A mensagem
# caiu no ramo de fotos e ele recebeu "o corretor Tel Sobreira pediu fotos do
# 150 e nao achei foto" -- resposta sobre ELE MESMO, e o imovel nao saiu.
#
# Palavra dele: "o codigo e 150 tem vezes que pode ser ate 2 numeros".
# MEDIDO no catalogo: 1 imovel de 2 digitos (o 45), 14 de 3, 1.238 de 4.
for t in [
    "envia 92 99462-9241  codigo 150",     # a frase exata, com espaco duplo
    "envia 92 99462-9241 codigo 150",
    "envia (92) 99462-9241 código 150",
    "Nay envia 92 99462-9241 cod 150",
    "Nay, envia 92 99462-9241 codigo: 150",
    "envia para 92 99462-9241 codigo 150",
    "manda 92 99462-9241 codigo 45",       # o unico de 2 digitos do catalogo
    "envia 92994629241 codigo 150",        # sem separador nenhum
    "envia 5592994629241 codigo 150",      # como o BANCO guarda o numero
]:
    checar(t, "enviar_para_corretor")

_r = _ic0("manda 92 99462-9241 codigo 45")
assert _r["codigos"] == ["45"], _r
print("  OK   dois digitos viram o codigo 45, nao pedaco do telefone")
_r = _ic0("manda (92) 99462-9241 código 150 e 45")
assert _r["codigos"] == ["150", "45"], _r
print("  OK   dois codigos na mesma frase")
_r = _ic0("envia 5592994629241 codigo 150")
assert _r["codigos"] == ["150"], f"o telefone virou codigo: {_r}"
print("  OK   o 55 do banco nao deixa sobrar '41' como codigo")

print()
print("--- mas DOIS DIGITOS SO com a palavra ---")
# "os 2" quer dizer "os dois" -- e a forma que desempata a lista, medida em
# 12/09. O minimo de 2 digitos ja a exclui (ela tem um digito so), mas o
# marcador e o que torna a licenca explicita em vez de acidental.
checar("envia 92 99462-9241 45", "nao_reconhecido",
       "numero solto de 2 digitos depois do telefone nao e codigo")
checar("envia 92 99462-9241 o 45", "nao_reconhecido",
       "nem com artigo: so a palavra codigo desce para dois digitos")
checar("envia 92 99462-9241 os 2", "nao_reconhecido",
       '"os 2" e a escolha da lista, nunca o imovel 2')

_r = _ic0("posta 92 99462-9241 codigo 150")
assert _r["acao"] == "postar_agora" and _r["codigos"] == ["150"], _r
print("  OK   posta com codigo: continua no caminho de grupo, e so o 150")

print()
print("--- TELEFONE ANTES DO VERBO (Tel, 24/09, duas vezes em minutos) ---")
# Ele abre pelo contato e so depois diz o que mandar. Nenhuma gramatica cobria
# isso -- todas esperam o verbo na frente -- e as duas frases morreram em
# "nao_reconhecido". O conserto e uma REESCRITA para a forma canonica, nao um
# parser novo: assim o pedido DESCRITO continua sendo resolvido por
# `pedido_de_imoveis`, sem uma segunda copia da regra de leitura.
from interpretar_comando import _telefone_antes_do_verbo as _tv

checar("92 9454-0289 ennvia todos os apartamentos no condominio verona "
       "para este número", "enviar_para_corretor")
checar("92 9951-9275 envia para ela o amazonas flat para locação de 2k",
       "enviar_para_corretor")
checar("92 9951-9275 manda pra ele o 5737", "enviar_para_corretor")
checar("(92) 99519275, envia o 5737", "enviar_para_corretor")
checar("5592994540289 encaminha o 3827 para esse número",
       "enviar_para_corretor")

_r = _ic0("92 9951-9275 manda pra ele o 5737")
assert _r["destino"] == "92 9951-9275", _r
assert _r["codigos"] == ["5737"], _r
print("  OK   o telefone da frente vira o DESTINO")
_r = _ic0("92 9951-9275 envia para ela o amazonas flat para locação de 2k")
assert _r["corpo"] == "o amazonas flat para locação de 2k", _r["corpo"]
print("  OK   e o 'para ela' nao disputa o destino com ele")

print()
print('--- "ennvia" e "mannda": letra repetida e o teclado, nao outra palavra ---')
# Recusar por causa de um "n" a mais custa um imovel nao enviado -- foi assim
# que a frase do Verona morreu. A tolerancia mora SO na reescrita: afrouxar o
# ENVIO_RE seria editar sete copias e criar sete chances de divergir.
checar("92 9454-0289 mannda o 3827 e o 3921", "enviar_para_corretor")
_r = _ic0("92 9454-0289 mannda o 3827 e o 3921")
assert _r["codigos"] == ["3827", "3921"], _r
print("  OK   dois códigos com o verbo torto")
checar("92 9454-0289 repassa o 3827", "enviar_para_corretor")

print()
print("--- e o que NAO pode virar envio por essa porta ---")
# Telefone sozinho, sem verbo de envio: e so alguem passando um numero.
checar("92 9951-9275 bom dia", "nao_reconhecido",
       "telefone sem verbo de envio não é comando")
checar("92 9951-9275 é o número dela", "nao_reconhecido")
checar("92 9951-9275 posta o 5737", "nao_reconhecido",
       "posta vai para grupo: nunca entra pela porta do envio privado")
# Codigo nao e telefone: "5719 e 5728" e a escolha da lista, medida em 12/09.
checar("5719 e 5728", "escolher_codigos")
_r = _tv("5719 e 5728")
assert _r is None, _r
print("  OK   código não é lido como telefone")
_r = _tv("2943 envia para o Sergio")
assert _r is None, _r
print("  OK   nem código de 4 dígitos seguido de verbo")

print()
print("--- A FONTE UNICA: os mesmos casos que o nó do n8n roda ---")
# `casos_telefone_na_frente.json` e lido por ESTE teste (Python) e por
# `teste_regex_telefone_na_frente.js` (Node do container). A gramatica vive em
# SEIS copias, em dois fluxos -- divergir entre elas e o bug que ja aconteceu
# tres vezes em 23/09. Com a fonte unica, divergencia vira teste vermelho em
# vez de comando morto.
import json as _json
from interpretar_comando import ENVIO_TELEFONE_NA_FRENTE_RE as _FRENTE
_casos = _json.load(open("casos_telefone_na_frente.json", encoding="utf-8"))
_maus = 0
for _t, _esp in _casos:
    _got = bool(_FRENTE.match(_t))
    if _got != _esp:
        _maus += 1
        print(f"  FALHOU {_t!r} -> {_got}, esperava {_esp}")
assert not _maus, f"{_maus} divergencias entre o Python e os casos"
print(f"  OK   os {len(_casos)} casos da fonte unica batem no Python")

# E a MESMA coisa para o telefone ANTES do verbo. O no do n8n so DETECTA (quem
# reescreve e o Python), entao os dois precisam concordar sobre o que e
# comando -- senao a frase vai ao modelo e o Tel recebe resposta sobre si
# mesmo, que foi o sintoma de 23/09.
from interpretar_comando import TELEFONE_ANTES_DO_VERBO_RE as _ANTES
_casos2 = _json.load(open("casos_telefone_antes_do_verbo.json", encoding="utf-8"))
_maus = 0
for _t, _esp in _casos2:
    _got = bool(_ANTES.match(_t))
    if _got != _esp:
        _maus += 1
        print(f"  FALHOU {_t!r} -> {_got}, esperava {_esp}")
assert not _maus, f"{_maus} divergencias no telefone antes do verbo"
print(f"  OK   os {len(_casos2)} casos do telefone antes do verbo batem")

print()
print("--- e o que NÃO pode virar envio por essa porta ---")
# Com NOME não casa, de propósito: "envia Sergio o 3210" e "envia [o] 3210
# [para] Sergio" não se distinguem sem adivinhar quem é o quê.
checar("envia Sergio o 3210", "nao_reconhecido",
       "sem telefone não dá para saber o que é destino e o que é imóvel")
# O verbo de GRUPO continua fora desta porta -- ela só aceita
# envi/mand/repass/encaminh --, então `posta` segue para o caminho dele.
#
# E ALI O TELEFONE NÃO PODE VIRAR CÓDIGO: antes de 23/09 a mesma frase dava
# os "códigos" ['92','98478','7190','3210'] e postaria em 19 grupos o imóvel
# que casasse por acaso. Um telefone terminado em 4500 postaria o 4500, que
# existe. É a mesma família do valor_nao_e_codigo.sql.
from interpretar_comando import interpretar_comando as _ic
_r = _ic("posta (92) 98478-7190 o 3210")
assert _r["acao"] == "postar_agora", _r
assert _r["codigos"] == ["3210"], f"o telefone virou código: {_r['codigos']}"
print("  OK   posta com telefone: só o 3210 vira código")
_r = _ic("publica no anunciar easy (92) 98478-7190 o 5750")
assert _r.get("codigo") == "5750", _r
print("  OK   e no Easy também")

print()
print("--- verbo de GRUPO com pessoa: recusa, nunca dispara ---")
for t in [
    "Nay posta o 5750 pro Rogerio",
    "publica o 5750 pra Samira",
    "solta os 3 do acquarelle pro corretor Paulo",
    "dispara o 2943 pro Leonan",
]:
    checar(t, "envio_recusado", "posta vai para 14 grupos; mandar para pessoa aqui seria desastre")

print()
print("--- horario no meio: recusa, nao vira vaga ---")
for t in [
    "Nay manda o 5750 pro Sergio todo dia as 9h",
    "envia o 5750 pra Samira as 14h",
]:
    checar(t, "envio_recusado", "vaga posta em GRUPO; misturar aqui postaria publicamente")

print()
print("--- o que NAO pode virar envio privado ---")
checar("Nay posta o 5750", "postar_agora")
checar("Nay publica no anunciar easy o 5750", "postar_easy")
checar("manda pro grupo de anunciar da easy 5750", "postar_easy",
       "cauda de GRUPO: a regressao que o teste pegou em 31/08")
checar("Nay, publicamos o 5750 ontem?", "nao_reconhecido",
       "pergunta no passado nunca vira comando -- bug de 27/08")
checar("Nay vagas", "listar_vagas")
checar("Nay tira o 5750", "remover_da_grade")
checar("Nay VENDEU 5750", "liberar_vaga")
checar("RESPOSTA 17 pode ser 15h", "nao_reconhecido")

print()
print("--- o destinatario extraido ---")
for texto, esperado in [
    ("Nay manda o 5750 pro Sergio", "Sergio"),
    ("Nay envia os acquarelle pro corretor Gustavo", "corretor Gustavo"),
    ("Nay envia todos os acquarelle para locacao para o Sergio", "o Sergio"),
]:
    obtido = ic(texto).get("destino")
    ok = obtido == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {texto[:46]:48s} -> {obtido!r}")
    if not ok:
        print(f"         esperava {esperado!r}")

print()
print("--- o corpo guloso pega a ULTIMA preposicao ---")
r = ic("Nay envia todos os acquarelle para locacao para o Sergio")
ok = "locacao" in (r.get("corpo") or "")
falhas += 0 if ok else 1
print(f"  {'OK  ' if ok else 'FALHOU'} 'para locacao' ficou no corpo, nao no destino")
if not ok:
    print(f"         corpo={r.get('corpo')!r} destino={r.get('destino')!r}")

print()
print("--- TELEFONE NA FRENTE + UM CÓDIGO é envio, mesmo com o verbo torto ---")
# O CASO (Tel, 28/09): ele escreveu "92 8192-5962 **evia** o 964" -- faltou o
# "n". Nenhuma gramática casou, a frase foi ao agente, e a Nay respondeu A ELE
# como se fosse um corretor pedindo o imóvel: "Bom dia, Imob! Claro, já te
# mando!", com o card e as 13 fotos. O imóvel nunca chegou à corretora.
#
# A palavra dele: "toda vez que vier mensagem da imob easy e do Tel é um
# comando para enviar o imóvel e não para receber, para ela não poder
# confundir e fazer isso".
#
# É SEGURO porque só mensagem DOS NÚMEROS DELE chega ao publicador: o nó que
# chama o `POST /comando` já conferiu quem escreveu. "Telefone na frente" aqui
# não é palpite sobre um estranho -- é ele dando um destino.
for _f in ["92 8192-5962 evia o 964",          # a frase exata que falhou
           "Nay 92 8192-5962 evia o 964",
           "@Nay 92 8192-5962 evia o 964",
           "92 8192-5962 enviaa o 964",
           "92 8192-5962 manda 964",
           "92 8192-5962 o 964",               # sem verbo nenhum
           "(92) 98192-5962 evia o 964",
           "5592981925962 evia o 964",
           "92981925962 964"]:
    checar(_f, "enviar_para_corretor")
# O destino e o código saem certos -- não adianta reconhecer e mandar errado.
_r = ic("92 8192-5962 evia o 964")
assert _r["destino"] == "92 8192-5962", _r
assert _r["codigos"] == ["964"], _r
print("  OK   o destino e o código saem certos")

print()
print("--- as três exigências, cada uma tirando um falso positivo medido ---")
# 1. COMEÇA com o telefone. Comandos legítimos do histórico dele (22 e 23/09).
for _f in ["NAO CORRETOR (92) 98427-1973  - ela nunca responde",
           "DEVOLVER (92) 99511-8525 estou verificando com a proprietária",
           "RESPOSTA (92) 99515-1318 WLYSSES apenas uma vaga",
           "CORRETOR (92) 99277-3833"]:
    checar(_f, "nao_reconhecido")
# 2. UM CÓDIGO SÓ, de 3 a 5 dígitos. Sem o piso, "uma casa de 4 mil" colhia
#    o "4" e mandaria o imóvel 4.
checar("Devolver (92) 98644-8395 temos uma casa na ponta negra de 4 mil",
       "nao_reconhecido")
checar("(92) 99515-1318 apenas uma vaga mesmo", "nao_reconhecido")
# 3. OUTRO COMANDO FECHA A PORTA. `posta` manda para os GRUPOS, e a regra de
#    31/08 é que postar e enviar para uma pessoa nunca se misturam.
checar("92 9951-9275 posta o 5737", "nao_reconhecido",
       "posta continua indo para grupo, nunca pela porta do envio privado")
checar("92 9951-9275 tira o 5737", "nao_reconhecido")
checar("92 9951-9275 vendeu o 5737", "nao_reconhecido")

print()
print("--- e o último recurso NÃO rouba comando nenhum ---")
for _f, _e in [("Nay posta o 5750", "postar_agora"),
               ("Nay VAGAS", "listar_vagas"),
               ("posta no grupo comercial 5763", "postar_comercial"),
               ("Nay manda o 5750 pro Sergio", "enviar_para_corretor"),
               ("92 8192-5962 envia o 964 e o 5717", "enviar_para_corretor")]:
    checar(_f, _e)


print()
print("TODOS OS TESTES PASSARAM" if falhas == 0 else f"{falhas} FALHARAM")
raise SystemExit(1 if falhas else 0)
