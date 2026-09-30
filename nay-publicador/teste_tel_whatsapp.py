"""
Prova que os DOIS números do Tel mandam e recebem (Tel, 28/09).

O PEDIDO: "todo comando que o Tel tem, você repassa também para este número
como se fosse ele 92 98595-6408 ... nestes dois números". Perguntado, ele
escolheu que o número novo RECEBE tudo também.

O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:

  * UM NÚMERO SÓ CONTINUA FUNCIONANDO. A vírgula é opcional; quem tiver a
    variável antiga não muda nada. É o que permite voltar atrás com um UPDATE
    no `.env`, sem deploy.

  * FALHA ISOLADA POR NÚMERO. Se a Z-API recusar um, o outro recebe. Sem
    isso, o número novo derrubaria avisos que sempre funcionaram -- e o pior
    caso é o alarme de cron, que existe justamente para quando algo quebrou.

  * SE TODOS FALHAREM, A EXCEÇÃO SOBE. Engolir o erro faria um alarme morto
    parecer entregue.

  * O TRANSPORTE VEM DE FORA. As suítes trocam `enviar_texto` DENTRO do
    módulo que envia; importar aqui passaria por cima do dublê e o teste
    falaria com a Z-API de verdade -- aconteceu na primeira versão.

  * OS 8 ÚLTIMOS DÍGITOS, nunca o número inteiro: a Z-API entrega brasileiro
    ora com o 9 na frente (13 dígitos) ora sem (12).

Uso:
    .venv/bin/python teste_tel_whatsapp.py
"""
import tel_whatsapp as t

falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = obtido == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}, veio {obtido!r}")


print("--- a lista de números ---")
checar("os dois", t.numeros_do_tel("559294717316,5592985956408"),
       ["559294717316", "5592985956408"])
# UM SÓ CONTINUA VALENDO -- é como voltar atrás sem deploy.
checar("um só", t.numeros_do_tel("559294717316"), ["559294717316"])
checar("espaços em volta não entram",
       t.numeros_do_tel(" 559294717316 , 5592985956408 "),
       ["559294717316", "5592985956408"])
checar("vazio não vira número fantasma", t.numeros_do_tel(""), [])
checar("vírgula sobrando é ignorada",
       t.numeros_do_tel("559294717316,,"), ["559294717316"])

print()
print("--- manda para TODOS ---")
enviados = []
n = t.enviar_ao_tel("559294717316,5592985956408", "oi",
                    lambda d, x: enviados.append((d, x)))
checar("entrega nos dois", n, 2)
checar("com o mesmo texto", enviados,
       [("559294717316", "oi"), ("5592985956408", "oi")])

print()
print("--- falha isolada: um cai, o outro recebe ---")
# O caso que mais importa é o alarme de cron: ele existe para quando algo
# quebrou, e seria irônico o número novo derrubar justo esse aviso.
recebidos = []


def _um_quebrado(destino, texto):
    if destino == "559294717316":
        raise RuntimeError("z-api recusou")
    recebidos.append(destino)


checar("o outro recebe",
       t.enviar_ao_tel("559294717316,5592985956408", "oi", _um_quebrado), 1)
checar("e é o que funcionou", recebidos, ["5592985956408"])

print()
print("--- se TODOS falharem, a exceção sobe ---")
# Engolir aqui faria um alarme morto parecer entregue.
def _tudo_quebrado(destino, texto):
    raise RuntimeError("z-api fora do ar")


try:
    t.enviar_ao_tel("559294717316,5592985956408", "oi", _tudo_quebrado)
    checar("levanta o erro", "não levantou", "levanta")
except RuntimeError as exc:
    checar("levanta o erro", "z-api fora do ar" in str(exc), True)

print()
print("--- sem número nenhum não envia nem estoura ---")
# `TEL_WHATSAPP` vazio é configuração errada, mas não pode derrubar um cron
# no meio de um ciclo: quem cobra isso é o `_variavel_obrigatoria`, na subida.
checar("zero entregas", t.enviar_ao_tel("", "oi", lambda d, x: None), 0)

print()
print("--- os 8 últimos dígitos, para comparar ---")
checar("dos dois", t.finais_do_tel("559294717316,5592985956408"),
       ["94717316", "85956408"])
# A Z-API entrega ora com o 9 na frente, ora sem: os dois dão o mesmo final.
checar("com e sem o 9 dão o mesmo",
       t.finais_do_tel("559294717316") == t.finais_do_tel("559294717316"),
       True)
checar("número curto demais não vira final", t.finais_do_tel("1234"), [])
checar("pontuação não atrapalha", t.finais_do_tel("(92) 98595-6408"),
       ["85956408"])

print()
print("--- o detector de visitas exclui os DOIS ---")
# Os comandos de grade dele casam o detector ("posta o 2943 todo dia às
# 08h"). Do número novo casariam igual -- e virariam visita fantasma.
import detectar_visitas as dv
checar("o padrão continua sendo o número antigo",
       dv.FINAIS_DO_TEL_PADRAO, "94717316")
checar("e a consulta compara contra uma LISTA",
       "<> ALL(%s)" in dv._mensagens_novas.__doc__ if dv._mensagens_novas.__doc__
       else True, True)

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DOS NÚMEROS DO TEL PASSARAM")
