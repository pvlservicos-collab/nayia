# -*- coding: utf-8 -*-
"""Poe "sem preferencia de bairro" na busca VIVA.

    python3 montar102.py perfil_vivo.sql 102b_busca_sem_bairro.sql

Le o `pg_get_functiondef` de `nai_buscar_por_perfil` e devolve o CREATE OR
REPLACE ja com o desvio. Montar aqui, e nao dentro de um DO, porque a aspa
simples do SQL dobrada dentro de string de PL/pgSQL dentro de heredoc de shell
deu erro tres vezes seguidas -- e um erro de aspa nao aparece em teste, aparece
no WhatsApp do corretor.
"""
import io, sys

t = io.open(sys.argv[1], encoding="utf-8").read().rstrip()
if t.endswith("$function$"):
    t += ";"


def troca(velho, novo, quantas=1):
    global t
    assert t.count(velho) == quantas, "nao achei (%d x %d): %s" % (t.count(velho), quantas, velho[:70])
    t = t.replace(velho, novo)


# 1. a variavel
troca("  v_mostra_logo boolean;   -- mostrar em vez de peneirar (100)",
      "  v_mostra_logo boolean;   -- mostrar em vez de peneirar (100)\n"
      "  v_livre  boolean;        -- procurar na cidade inteira (102)")

# 2. a decisao, junto com a da 100
troca("  v_mostra_logo := nai_pede_os_valores(",
      "  -- SEM PREFERENCIA DE BAIRRO (102, Tel 23/09). \"Nao teria preferencia por\n"
      "  -- bairro\" nao era resposta aceita: a sequencia exigia um bairro, entao ela\n"
      "  -- repetia a pergunta -- e repetiu, duas vezes, para a Deborah. Depois o\n"
      "  -- modelo mandou \"Manaus\" como bairro e a busca antiga respondeu que NAO\n"
      "  -- TRABALHAMOS COM IMOVEL EM MANAUS. A cidade nunca e bairro.\n"
      "  v_livre := nai_e_a_cidade(p_bairro)\n"
      "             OR nai_sem_preferencia_de_bairro(concat_ws(' ', p_bairro, t.texto));\n"
      "  v_mostra_logo := nai_pede_os_valores(")

# 3. a pergunta do bairro
troca("  IF nullif(btrim(coalesce(p_bairro, '')), '') IS NULL THEN",
      "  IF nullif(btrim(coalesce(p_bairro, '')), '') IS NULL AND NOT v_livre THEN")

# 4. a busca principal passa a varrer a cidade
# O mesmo WHERE aparece duas vezes: aqui e, com outro recuo, na busca do nome
# do bairro para a frase. Por isso a ancora leva o FROM junto.
ALVO4 = ("      FROM imoveis i\n"
         "     WHERE nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'")
troca(ALVO4,
      ALVO4.replace("     WHERE nay_", "     WHERE (v_livre OR nay_") + ")")

# 5. sem bairro nao existe "aqui perto"
troca("  v_viz := nay_bairros_proximos(btrim(coalesce(p_bairro, '')));",
      "  v_viz := CASE WHEN v_livre THEN '{}'::text[]\n"
      "                ELSE nay_bairros_proximos(btrim(coalesce(p_bairro, ''))) END;")

# 6. a busca antiga NUNCA recebe a cidade como bairro
troca("    SELECT * INTO b FROM nay_buscar_por_perfil(p_bairro,",
      "    -- A busca antiga so sabe responder SOBRE UM BAIRRO (\"voce quis dizer\n"
      "    -- Ponta Negra?\", \"esse bairro nao e da nossa area\"). Sem bairro, ela\n"
      "    -- diria a frase proibida com o nome da cidade dentro.\n"
      "    IF v_livre THEN\n"
      "      RETURN QUERY SELECT\n"
      "        ('Não tenho nada nesse perfil disponível no momento. Me diz até que valor '\n"
      "         || 'o cliente vai, que eu procuro em toda a cidade.')::text,\n"
      "        ('ele nao tem bairro preferido e nao achei nada: peca a faixa de preco. '\n"
      "         || 'NUNCA diga que nao trabalhamos em Manaus -- a imobiliaria e de Manaus.')::text;\n"
      "      RETURN;\n"
      "    END IF;\n"
      "    SELECT * INTO b FROM nay_buscar_por_perfil(p_bairro,")

# 7. o texto da lista
troca("    v_txt := 'No ' || v_nome_b || ' eu tenho estas opções:' || E'\\n\\n' || v_aqui;",
      "    v_txt := CASE WHEN v_livre THEN 'Tenho estas opções:'\n"
      "                  ELSE 'No ' || v_nome_b || ' eu tenho estas opções:' END\n"
      "             || E'\\n\\n' || v_aqui;")

io.open(sys.argv[2], "w", encoding="utf-8", newline="\n").write(t + "\n")
print("102b montado: %d chars" % len(t))
