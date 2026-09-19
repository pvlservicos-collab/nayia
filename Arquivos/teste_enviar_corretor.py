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
print("TODOS OS TESTES PASSARAM" if falhas == 0 else f"{falhas} FALHARAM")
raise SystemExit(1 if falhas else 0)
