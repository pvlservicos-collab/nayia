# -*- coding: utf-8 -*-
"""Teste do vigia do WhatsApp com uma Z-API de mentira: nada sai de verdade.

    python scripts/servidor/teste_vigia_whatsapp.py

Conta a história de 02/10: o número cai, a fila fica presa, o número volta.
"""
import os
import sys
import tempfile

PASTA = tempfile.mkdtemp(prefix="vigia_teste_")
os.environ["VIGIA_RAIZ"] = PASTA
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vigia_whatsapp as v  # noqa: E402

CONF = dict(v.PADRAO, grupo="120000000000000000-group", instancias={
    "parceria": {"rotulo": "Nay de Parceria", "final": "3618", "base": "P", "client_token": "x", "vizinha": "captacao", "banco": True},
    "captacao": {"rotulo": "Nay de Captação", "final": "6408", "base": "C", "client_token": "x", "vizinha": "parceria", "banco": False},
})


class ZapiDeMentira:
    def __init__(self):
        self.conectada = {"P": True, "C": True}
        self.fila = {"P": [], "C": []}
        self.enviadas = []        # (instância, rota, corpo)
        self.apagou = 0
        self.falhar_envio_para = set()
        self.n = 0

    def __call__(self, inst, metodo, caminho, corpo=None, timeout=20):
        b = inst["base"]
        if caminho == "/status":
            return {"connected": self.conectada[b]}
        if caminho.startswith("/queue") and metodo == "GET":
            return list(self.fila[b]) if "page=1&" in caminho else []
        if caminho == "/queue" and metodo == "DELETE":
            self.apagou += 1
            self.fila[b] = []
            return {"value": True}
        if metodo == "POST":
            self.n += 1
            if corpo["phone"] in self.falhar_envio_para:
                return {"error": "recusado"}
            self.enviadas.append((b, caminho, corpo))
            return {"messageId": "NOVO%d" % self.n, "zaapId": "Z%d" % self.n}
        raise AssertionError("chamada inesperada: %s %s" % (metodo, caminho))


zapi = ZapiDeMentira()
sql = []
dormiu = []
v.api = zapi
v.psql = lambda banco, s: (sql.append((banco, s)), None)[1]
v.time.sleep = lambda s: dormiu.append(s)
v.log = lambda nome, msg: None


def avisos():
    return [c["message"] for b, rota, c in zapi.enviadas if c["phone"] == CONF["grupo"]]


def confere(cond, o_que):
    print(("ok   " if cond else "FALHOU ") + o_que)
    if not cond:
        sys.exit(1)


# 1. tudo bem: nada acontece
v.rodar("parceria", CONF)
confere(not zapi.enviadas, "conectada: nenhum aviso")

# 2. uma leitura ruim só não é queda
zapi.conectada["P"] = False
zapi.fila["P"] = [
    {"Phone": "5592999997527", "Message": "📍 Condomínio X\nCódigo: 3050", "MessageId": "3EB0A1F00D", "ZaapId": "01A0ZA1", "Created": (v.time.time() - 600) * 1000},
    {"Phone": "5592999997527", "Image": "https://imobeasy.com/f/1.jpg", "MessageId": "3EB0A2F00D", "ZaapId": "01A0ZA2", "Created": (v.time.time() - 590) * 1000},
    {"Phone": "5592999997062", "Message": "já te respondo", "MessageId": "3EB0A3F00D", "Created": (v.time.time() - 500) * 1000},
]
v.rodar("parceria", CONF)
confere(not avisos() and zapi.apagou == 0, "primeira leitura desconectada: ainda não avisa nem mexe na fila")

# 3. segunda leitura: caiu. Avisa pelo OUTRO número, guarda a fila e limpa a da Z-API
v.rodar("parceria", CONF)
confere(len(avisos()) == 1 and "A NAY CAIU" in avisos()[0] and "Nay de Parceria" in avisos()[0], "queda: um aviso claro no grupo")
confere(zapi.enviadas[-1][0] == "C", "o aviso saiu pelo número da captação (o outro)")
confere(zapi.apagou == 1 and zapi.fila["P"] == [], "a fila da Z-API foi limpa")
confere(len(v.ler_json(v.arquivo("fila", "parceria"), [])) == 3, "as 3 mensagens ficaram guardadas no disco")

# 4. continua fora: não repete o aviso a cada minuto; o que entrar de novo na fila também é guardado
zapi.fila["P"] = [{"Phone": "5592999997321", "Message": "oi, segue", "MessageId": "3EB0A4F00D", "Created": v.time.time() * 1000}]
v.rodar("parceria", CONF)
confere(len(avisos()) == 1, "minuto seguinte: sem aviso repetido")
confere(len(v.ler_json(v.arquivo("fila", "parceria"), [])) == 4 and zapi.fila["P"] == [], "mensagem nova presa também foi guardada")

# 5. meia hora depois: lembrete (em horário de gente)
est = v.ler_json(v.arquivo("estado", "parceria"), {})
est["ultimo_aviso"] = v.time.time() - 31 * 60
v.gravar_json(v.arquivo("estado", "parceria"), est)
agora_de_verdade = v.agora
v.agora = lambda: agora_de_verdade().replace(hour=15)
v.rodar("parceria", CONF)
confere(len(avisos()) == 2 and "continua" in avisos()[1] and "4 mensagem" in avisos()[1], "lembrete depois de 30 min, com quantas estão guardadas")

# 6. voltou: avisa e reenvia DEVAGAR (com espera entre uma e outra), trocando o id no banco
zapi.conectada["P"] = True
zapi.falhar_envio_para = set()
v.rodar("parceria", CONF)
para_gente = [(b, rota, c) for b, rota, c in zapi.enviadas if c["phone"] != CONF["grupo"]]
confere(any("A Nay voltou" in a for a in avisos()), "volta: aviso no grupo")
confere(any("Guardei 4 mensagem" in a and "3 pessoa" in a for a in avisos()), "o aviso da volta diz quantas vai reenviar e para quantas pessoas")
confere(len(para_gente) >= 1 and all(b == "P" for b, _, _ in para_gente), "o reenvio sai pelo próprio número que voltou")
confere(para_gente[0][1] == "/send-text" and "Código: 3050" in para_gente[0][2]["message"], "a primeira é o card (a ordem da fila é mantida)")

# as rodadas seguintes terminam a fila
for _ in range(6):
    v.rodar("parceria", CONF)
para_gente = [(b, rota, c) for b, rota, c in zapi.enviadas if c["phone"] != CONF["grupo"]]
confere(len(para_gente) == 4, "as 4 guardadas foram reenviadas, nenhuma em dobro (saíram %d)" % len(para_gente))
confere(para_gente[1][1] == "/send-image" and para_gente[1][2]["image"].endswith("1.jpg"), "a foto foi como foto")
confere(len(dormiu) >= 3 and all(0 < s <= CONF["intervalo_s"] for s in dormiu), "esperou entre uma e outra (%d esperas de até %d s)" % (len(dormiu), CONF["intervalo_s"]))
confere(sum("nai_whatsapp_reenviado" in s for b, s in sql if b == "naydb") == 4, "trocou o id das 4 na caixa da Nay")
confere(sum("zapi_message_id" in s for b, s in sql if b == "crmdb") == 4, "trocou o id das 4 no CRM")
confere(any("Fila da" in a and "reenviada: 4" in a for a in avisos()), "aviso final: fila reenviada")
confere(v.ler_json(v.arquivo("fila", "parceria"), [1]) == [], "nada sobrou guardado")
confere(zapi.apagou == 2, "a fila da Z-API só foi apagada enquanto o número estava fora")

# 7. mensagem velha demais não é reenviada; a que a Z-API recusa é contada
zapi.enviadas.clear()
v.gravar_json(v.arquivo("fila", "parceria"), [
    v.entrada_da_fila({"Phone": "5592911112222", "Message": "de ontem", "MessageId": "3EB0V1F00D", "Created": (v.time.time() - 20 * 3600) * 1000}),
    v.entrada_da_fila({"Phone": "5592933334444", "Message": "essa vai", "MessageId": "3EB0V2F00D", "Created": v.time.time() * 1000}),
])
est = v.ler_json(v.arquivo("estado", "parceria"), {})
est["ultimo_reenvio"] = 0
v.gravar_json(v.arquivo("estado", "parceria"), est)
v.rodar("parceria", CONF)
para_gente = [c for b, rota, c in zapi.enviadas if c["phone"] != CONF["grupo"]]
confere([c["message"] for c in para_gente] == ["essa vai"], "mensagem de 20 horas atrás não foi reenviada; a nova foi")
confere(any("1 antiga" in a and "2222" in a for a in avisos()), "o aviso final conta a que não foi e para qual final")

# 8. fora do horário (23h) não reenvia nada
zapi.enviadas.clear()
v.gravar_json(v.arquivo("fila", "parceria"), [v.entrada_da_fila({"Phone": "5592955556666", "Message": "tarde da noite", "MessageId": "3EB0N1F00D", "Created": v.time.time() * 1000})])
v.agora = lambda: agora_de_verdade().replace(hour=23)
v.rodar("parceria", CONF)
confere(not zapi.enviadas, "23h: guarda e espera a manhã")
v.agora = lambda: agora_de_verdade().replace(hour=15)

# 9. o outro número também está fora: o aviso fica pendente em vez de ir para a fila dele
zapi.enviadas.clear()
os.remove(v.arquivo("fila", "parceria"))
zapi.conectada.update(P=False, C=False)
v.rodar("parceria", CONF)
v.rodar("parceria", CONF)
confere(not zapi.enviadas and v.ler_json(v.arquivo("estado", "parceria"), {}).get("aviso_pendente") is True, "os dois fora: aviso fica pendente (não entra em fila morta)")
zapi.conectada["C"] = True
v.rodar("parceria", CONF)
confere(len(avisos()) == 1 and "A NAY CAIU" in avisos()[0], "o outro voltou: o aviso pendente sai")

# 10. a Z-API não responde: não se conclui queda
zapi.conectada["P"] = True
v.rodar("parceria", CONF)
zapi.enviadas.clear()
real = v.api
v.api = lambda inst, metodo, caminho, corpo=None, timeout=20: {"_erro": "URLError"}
for _ in range(4):
    v.rodar("parceria", CONF)
v.api = real
confere(v.ler_json(v.arquivo("estado", "parceria"), {}).get("estado") == "ok" and not zapi.enviadas, "Z-API sem resposta não vira alarme falso")

print("\ntudo certo (%s)" % PASTA)
