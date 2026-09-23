# -*- coding: utf-8 -*-
"""Casa nao e apartamento: fecha a ultima porta por onde o tipo errado saia.

    python3 montar103.py perfil_vivo.sql 103_casa_nao_e_apartamento.sql

O CASO (Geina, (92) 9182-4643, 23/09/2026 09:38). Ela pediu, por audio,
"casa para aluguel" ate 4 mil no Alvorada e vizinhos. A Nay procurou CASA,
nao achou no bairro nem perto, e caiu na busca ANTIGA -- `nay_buscar_por_perfil`,
que nao tem filtro de tipo. A busca antiga devolveu APARTAMENTOS:

    • Ariranhas (Da Paz) — 2 quartos — 2.600 — Codigo: 5729
    • Vistas dos Cedros (Planalto) — 2 quartos — 2.500 — Codigo: 5743

O filtro de tipo entrou em 22/09 (98) e vale na busca nova, nas duas camadas
-- o bairro e os vizinhos. Faltava esta terceira saida, que ninguem tinha
olhado porque so aparece quando NAO HA NADA do tipo pedido.

Tel: "preciso que haja uma organizacao melhor do banco de dados, dividindo so
o que e casa e o que e apartamento para ela nao mandar apartamento para quem
pede casa, isso e um erro feio".

O dado ja esta dividido (`imoveis.tipo`): 'Casa' e 'Casa de condominio' de um
lado, 'Apartamento' e 'Apartamento em Via Publica' do outro. O que faltava era
o caminho respeitar isso ate o fim. Agora, quando nao ha o tipo pedido, ela
DIZ que nao ha -- e nao troca por outro tipo.
"""
import io, sys

t = io.open(sys.argv[1], encoding="utf-8").read().rstrip()
if t.endswith("$function$"):
    t += ";"


def troca(velho, novo, quantas=1):
    global t
    assert t.count(velho) == quantas, "nao achei (%d x %d): %s" % (t.count(velho), quantas, velho[:70])
    t = t.replace(velho, novo)


ALVO = "    SELECT * INTO b FROM nay_buscar_por_perfil(p_bairro,"

troca(ALVO,
      "    -- CASA NAO E APARTAMENTO (103, Tel 23/09). A busca antiga nao conhece\n"
      "    -- tipo de imovel: chamada aqui, ela devolveu apartamento para quem pediu\n"
      "    -- casa. Quando o tipo foi pedido, quem responde e esta funcao -- dizendo\n"
      "    -- que nao tem, que e a verdade.\n"
      "    IF v_tipo IS NOT NULL THEN\n"
      "      RETURN QUERY SELECT\n"
      "        ('N' || CASE WHEN nullif(btrim(coalesce(p_bairro, '')), '') IS NULL\n"
      "                     THEN 'ão tenho ' || v_nada\n"
      "                     ELSE 'o ' || initcap(btrim(p_bairro)) || ' não tenho ' || v_nada END\n"
      "         || ' nesse perfil, nem nos bairros aqui perto.')::text,\n"
      "        ('ele pediu ' || coalesce(v_rotulo, 'um tipo de imovel')\n"
      "         || ' e nao existe nenhum(a) nesse perfil. NAO ofereca outro tipo no lugar. '\n"
      "         || 'Pergunte se ele aceita outro bairro ou outra faixa de preco.')::text;\n"
      "      RETURN;\n"
      "    END IF;\n"
      + ALVO)

io.open(sys.argv[2], "w", encoding="utf-8", newline="\n").write(t + "\n")
print("103 montado: %d chars" % len(t))
