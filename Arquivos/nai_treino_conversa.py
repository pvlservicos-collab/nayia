#!/usr/bin/env python3
"""
Roda CONVERSAS SIMULADAS inteiras pelo fluxo real do n8n (Tel, 22/09/2026).

    "quero que voce crie as variacoes possiveis de conversa como se fosse
     simulando meus clientes na proxima rodada e va estendendo a conversa
     com a Nay ate o final para testarmos todo o fluxo"

O irmao `nai_treino_rodar.py` reentrega UMA mensagem real por caso. Este
aqui pega um ROTEIRO (varios passos de um corretor simulado) e entrega um
passo de cada vez, sempre DEPOIS da resposta dela ao anterior e na MESMA
conversa -- a memoria so e zerada entre uma conversa e outra.

Tudo que importa para seguranca vem do irmao, sem copia: `conferir_travas`
(recusa rodar sem envio_simulado='sim'), o espelho, a entrega no webhook e a
espera pelo fim da resposta. NADA SAI PARA O WHATSAPP.

Cada passo vira um caso do ciclo, para o Tel julgar mensagem a mensagem. O
`contexto` do caso e a conversa ate ali, dos dois lados.

Os roteiros moram num JSON (Arquivos/treino_roteiros_rodada7.json). Num
passo, {cod1} e {cod2} viram o 1o e o 2o codigo de imovel que ELA citou na
ultima resposta; sem codigo nenhum, vale o texto de "senao".

Uso, no servidor:
    python3 nai_treino_conversa.py --roteiros treino_roteiros_rodada7.json \
        --rotulo "Rodada de treino 7"
    python3 nai_treino_conversa.py --roteiros ... --so 04-condominio-dois-e-fotos-de-novo
"""

import argparse
import json
import re
import sys
import time

import psycopg2.extras

from nai_treino_rodar import (ESPELHO_PADRAO, WEBHOOK_PADRAO, conectar,
                              conferir_travas, entregar, espelho_id,
                              esperar_turno, executar, garantir_corretor,
                              limpar_conversa, um)

# os jeitos que ela escreve um codigo: card ("Codigo: 5733"), bloco da busca
# ("#5733*"), lista nova ("*Imovel 5733*") e lista antiga ("• 5733 —")
RE_COD = re.compile(r"(?:#|Im[oó]vel\s+|C[oó]digo:\s*|•\s*)(\d{3,5})\b")


def codigos(texto):
    vistos = []
    for m in RE_COD.finditer(texto or ""):
        if m.group(1) not in vistos:
            vistos.append(m.group(1))
    return vistos


def montar_texto(conn, passo, ultima, contato_esp):
    texto = passo if isinstance(passo, str) else passo["texto"]
    cods = codigos(ultima)
    precisa = re.findall(r"\{cod(\d)\}", texto)
    if precisa and any(int(n) > len(cods) for n in precisa):
        return (passo.get("senao") if isinstance(passo, dict) else None) or texto
    for n in precisa:
        texto = texto.replace("{cod%s}" % n, cods[int(n) - 1])
    # {visita} e {imovel}: a visita aberta do espelho e o imovel dela. E o que
    # o comando do Tel precisa -- "VISITA 123 OK", "ACESSO 5727 ...".
    if "{visita}" in texto or "{imovel}" in texto:
        v = um(conn, "SELECT id, codigo FROM nai_visita WHERE corretor_id = %s "
                     "   AND nai_visita_aberta(estado) ORDER BY id DESC LIMIT 1", (contato_esp,))
        texto = texto.replace("{visita}", str(v["id"]) if v else "0")
        texto = texto.replace("{imovel}", str(v["codigo"]) if v else (cods[0] if cods else "0"))
    return texto


def rodar_roteiro(conn, ciclo, r, webhook, espelho, contato_esp, sessao, pausa):
    print("\n=== %s  (%s)  -- %s" % (r["id"], r["persona"], r.get("cobre", "")))
    executar(conn, "UPDATE nai_contato SET nome_whatsapp = %s, nome_completo = NULL "
                   " WHERE id = %s", (r["persona"], contato_esp))
    limpar_conversa(conn, contato_esp, sessao)
    executar(conn, "DELETE FROM nai_memoria WHERE session_id = %s", (sessao,))

    conversa, ultima, calada_seguida = [], "", 0
    for i, passo in enumerate(r["passos"], 1):
        texto = montar_texto(conn, passo, ultima, contato_esp)
        # Passo do TEL: entra pelo numero de comando. E o que fecha a visita
        # ("VISITA 12 OK"); sem ele a confirmacao nunca chega ao corretor.
        de_tel = isinstance(passo, dict) and passo.get("como") == "tel"
        if de_tel:
            fone = um(conn, "SELECT split_part(nai_cfg('comando_telefones', ''), ',', 1) AS f")["f"]
            alvo, nome_quem = espelho_id(conn, fone), "Tel"
        else:
            fone, alvo, nome_quem = espelho, contato_esp, r["persona"]
        caso = um(conn, """
            INSERT INTO nai_treino_caso (ciclo_id, contato_origem, papel, quando_original,
                                         ele_disse, contexto, roteiro, passo, persona, estado)
            VALUES (%s, %s, 'corretor', now(), %s, %s, %s, %s, %s, 'rodando') RETURNING id
        """, (ciclo, contato_esp, texto, psycopg2.extras.Json(conversa),
              r["id"], i, "Tel (comando)" if de_tel else r["persona"]))["id"]
        print("  [%d/%d] %s: %s" % (i, len(r["passos"]), "TEL" if de_tel else "ele",
                                    texto[:90].replace("\n", " ")))

        ultimo = um(conn, "SELECT coalesce(max(id),0) AS id FROM nai_turno "
                          " WHERE contato_id = %s", (alvo,))["id"]
        try:
            entregar(webhook, fone, nome_quem, texto)
            turno, erro = esperar_turno(conn, alvo, ultimo)
        except Exception as e:                      # noqa: BLE001
            turno, erro = None, str(e)[:900]
        if erro:
            porta = um(conn, "SELECT nai_tel_com_a_conversa(%s) AS tel, "
                             "       (SELECT humano_motivo FROM nai_contato WHERE id = %s) AS motivo",
                       (contato_esp, contato_esp))
            if "nao abriu turno" in erro and porta and porta["tel"]:
                # comportamento CERTO: a conversa passou para o Tel (escalada,
                # visita urgente). Marcar como erro faria o painel dizer
                # "falhou" para o que estava certo.
                executar(conn, "UPDATE nai_treino_caso SET estado='calada', erro=%s, rodado_em=now() "
                               " WHERE id=%s",
                         ("a conversa passou para o Tel" +
                          (" (%s)" % porta["motivo"] if porta["motivo"] else ""), caso))
                print("        calada: a conversa passou para o Tel")
            else:
                executar(conn, "UPDATE nai_treino_caso SET estado='erro', erro=%s WHERE id=%s",
                         (erro, caso))
                print("        ERRO: %s" % erro)
            ultima = ""
        else:
            ultima = um(conn, "SELECT nai_treino_colher(%s, %s) AS t", (caso, turno))["t"] or ""
            fotos = um(conn, "SELECT count(*) AS n FROM nai_saida WHERE turno_id=%s AND tipo='imagem'",
                       (turno,))["n"]
            print("        ela: %s%s" % ((ultima or "(calada)")[:110].replace("\n", " "),
                                        "  [+%d fotos]" % fotos if fotos else ""))

        conversa = conversa + [{"lado": "dele",
                                "texto": ("[comando do Tel] " if de_tel else "") + texto}]
        if ultima:
            conversa = conversa + [{"lado": "dela", "texto": ultima}]
            calada_seguida = 0
        else:
            calada_seguida += 1
        # Duas caladas seguidas: a conversa passou para o Tel (ou ela encerrou).
        # Seguir mandando so enche o painel de "(calada)" sem testar nada.
        if calada_seguida >= 2 and i < len(r["passos"]):
            print("        duas caladas seguidas -- a conversa saiu da mao dela, paro aqui")
            break
        time.sleep(pausa)


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    p.add_argument("--roteiros", required=True)
    p.add_argument("--rotulo", default="Conversas simuladas")
    p.add_argument("--so", help="roda so este roteiro (pelo id)")
    p.add_argument("--webhook", default=WEBHOOK_PADRAO)
    p.add_argument("--espelho", default=ESPELHO_PADRAO)
    p.add_argument("--pausa", type=float, default=3.0)
    args = p.parse_args()

    with open(args.roteiros, encoding="utf-8") as f:
        roteiros = json.load(f)["roteiros"]
    if args.so:
        roteiros = [r for r in roteiros if r["id"] == args.so]
        if not roteiros:
            sys.exit("nao achei o roteiro %s" % args.so)

    conn = conectar()
    conferir_travas(conn, args.espelho)
    contato_esp = espelho_id(conn, args.espelho)
    if garantir_corretor(conn, args.espelho):
        print("espelho registrado em `corretores`")
    sessao = "nai:corretor:%d" % contato_esp

    total = sum(len(r["passos"]) for r in roteiros)
    ciclo = um(conn, "INSERT INTO nai_treino_ciclo (rotulo, tamanho) VALUES (%s, %s) RETURNING id",
               (args.rotulo, total))["id"]
    print("ciclo %d: %d conversas, %d passos" % (ciclo, len(roteiros), total))

    inicio = time.time()
    for r in roteiros:
        rodar_roteiro(conn, ciclo, r, args.webhook, args.espelho, contato_esp, sessao, args.pausa)

    # tamanho real: conversa que parou antes (duas caladas) tem menos passos
    executar(conn, "UPDATE nai_treino_ciclo c SET tamanho = "
                   "(SELECT count(*) FROM nai_treino_caso k WHERE k.ciclo_id = c.id) WHERE c.id = %s",
             (ciclo,))
    executar(conn, "UPDATE nai_contato SET nome_whatsapp = 'Treino (espelho)' WHERE id = %s",
             (contato_esp,))
    print("\nterminou: ciclo %d em %.1f min" % (ciclo, (time.time() - inicio) / 60))


if __name__ == "__main__":
    main()
