"""
Prova que o aviso de ALUGADO/VENDIDO sai por qualquer caminho.

O QUE O TEL VIU (28/09): mandou `alugado 5737` pelo número da Imob Easy, a Nay
respondeu "Tirei do ar (alugado): 5737 — Amazonas Flat" e **não avisou no grupo
IMÓVEIS PARA ANUNCIAR EASY**. Os corretores que pegaram aquele anúncio para
divulgar continuam divulgando um imóvel que não existe mais.

A CAUSA: dois caminhos para "o imóvel saiu", e só um avisava. `alugado 5737`
casa `nai_e_comando_imovel`, então fica na NAI -- que marca indisponível e sabe
desfazer, mas não fala com grupo. O aviso mora no publicador.

O QUE IMPORTA PROVAR:

  * RESERVA ANTES DE MANDAR. O cron roda de minuto em minuto; entre "vi que
    devia" e "avisei" cabe outra rodada, e o grupo receberia duas vezes.
    Postagem em grupo não desfaz.

  * DEVOLVE À FILA SÓ QUANDO NADA SAIU. Se parte foi para o grupo, devolver
    faria o aviso sair de novo.

  * SIMULAÇÃO NÃO MANDA (regra 4 do projeto).

  * O TEXTO É O MESMO do comando na mão. Duas redações do mesmo aviso
    divergiriam na primeira edição.

Uso:
    .venv/bin/python teste_avisar_saidas.py
"""
import avisar_saidas as A

falhas = 0


def checar(titulo, obtido, esperado):
    global falhas
    ok = obtido == esperado
    falhas += 0 if ok else 1
    print(f"  {'OK  ' if ok else 'FALHOU'} {titulo}")
    if not ok:
        print(f"         esperava {esperado!r}, veio {obtido!r}")


class ConnFake:
    def __init__(self, fila, reserva=True):
        self.fila = list(fila)
        self.reserva = reserva
        self.reservados = []
        self.devolvidos = []

    def cursor(self):
        conn = self

        class C:
            def __enter__(s):
                return s

            def __exit__(s, *a):
                return False

            def execute(s, sql, params=None):
                if "nay_saidas_a_avisar" in sql:
                    s.r = list(conn.fila)
                elif "nay_reservar_aviso_de_saida" in sql:
                    conn.reservados.append(params[0])
                    s.r = [{"ok": conn.reserva}]
                elif "nay_devolver_aviso_de_saida" in sql:
                    conn.devolvidos.append(params[0])
                    s.r = []
                else:
                    s.r = []

            def fetchall(s):
                return s.r

            def fetchone(s):
                return s.r[0] if s.r else None
        return C()

    def commit(self):
        pass


FILA = [{"codigo": "5737", "motivo": "alugado"},
        {"codigo": "2943", "motivo": "vendido"}]

print("--- manda o aviso de cada saída pendente ---")
mandados = []
conn = ConnFake(FILA)
feitos = A.avisar(conn, enviar=True,
                  avisar_um=lambda c, k, m: mandados.append((c, m)) or f'avisei no Easy: {c}')
checar("avisa os dois", [c for c, _ in mandados], ["5737", "2943"])
checar("com o motivo certo", [m for _, m in mandados], ["alugado", "vendido"])
checar("e relata", [f[0] for f in feitos], ["5737", "2943"])

print()
print("--- RESERVA ANTES DE MANDAR ---")
# O cron roda de minuto em minuto. Sem a reserva, duas rodadas juntas
# avisariam duas vezes no grupo -- e grupo não desfaz.
checar("reservou cada um antes", conn.reservados, ["5737", "2943"])
# Quem não conseguiu a reserva não manda: outra rodada já pegou.
conn2 = ConnFake(FILA, reserva=False)
mandados2 = []
A.avisar(conn2, enviar=True, avisar_um=lambda c, k, m: mandados2.append(c) or "ok")
checar("sem reserva, não manda", mandados2, [])

print()
print("--- DEVOLVE À FILA só quando NADA saiu ---")
conn3 = ConnFake([{"codigo": "5737", "motivo": "alugado"}])
A.avisar(conn3, enviar=True,
         avisar_um=lambda c, k, m: "NÃO consegui avisar no grupo Easy (timeout)")
checar("erro total devolve", conn3.devolvidos, ["5737"])
# Sucesso não devolve -- devolver faria o aviso sair de novo.
conn4 = ConnFake([{"codigo": "5737", "motivo": "alugado"}])
A.avisar(conn4, enviar=True, avisar_um=lambda c, k, m: 'avisei no Easy: "..."')
checar("sucesso não devolve", conn4.devolvidos, [])
# EXCEÇÃO também devolve: nada saiu.
conn5 = ConnFake([{"codigo": "5737", "motivo": "alugado"}])
A.avisar(conn5, enviar=True,
         avisar_um=lambda c, k, m: (_ for _ in ()).throw(RuntimeError("caiu")))
checar("exceção devolve", conn5.devolvidos, ["5737"])

print()
print("--- simulação não manda (regra 4) ---")
conn6 = ConnFake(FILA)
mandados6 = []
feitos6 = A.avisar(conn6, enviar=False, avisar_um=lambda c, k, m: mandados6.append(c) or "ok")
checar("não mandou nada", mandados6, [])
checar("nem reservou", conn6.reservados, [])
checar("mas mostra o que faria", [f[0] for f in feitos6], ["5737", "2943"])

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DO AVISO DE SAÍDA PASSARAM")
