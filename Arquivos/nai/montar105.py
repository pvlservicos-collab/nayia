# -*- coding: utf-8 -*-
"""Uma busca so. Tira a busca ANTIGA do caminho do corretor.

    python3 montar105.py perfil_vivo.sql 105_uma_busca_so.sql

Tel, 23/09/2026: "mas nao e para ocorrer esse tipo de dupla busca, se eu
coloco regra e para seguir pow ta maluco? restrutura isso direito nao quero
esse tipo de erro".

Ele esta certo. Existiam DUAS buscas no mesmo caminho:

  `nai_buscar_por_perfil`  -- a nova. Respeita tipo (casa x apartamento),
                              finalidade (venda x locacao), faixa do teto,
                              mobilia, quartos, parceria e o que ja foi
                              mandado para aquele corretor nos ultimos 30 dias.

  `nay_buscar_por_perfil`  -- a antiga. Nao conhece NADA disso. So sabe bairro,
                              negocio, teto, quartos e mobilia.

E a nova chamava a antiga como saida de emergencia, quando nao achava nada.
Ou seja: toda regra que o Tel pos valia ate o momento em que mais importava --
quando nao ha o que ele pediu. Foi por ai que sairam dois apartamentos para a
Geina, que pediu casa.

Agora a busca e uma so. Quando nao ha, ela diz que nao ha; quando o bairro
nao existe no catalogo, ela pergunta se ele quis dizer outro; e o nome da
cidade nunca vira "nao trabalhamos em Manaus".

A funcao antiga continua existindo no banco -- outros lugares fora do
atendimento ainda a usam --, mas nao responde mais corretor nenhum.
"""
import io, sys

t = io.open(sys.argv[1], encoding="utf-8").read().rstrip()
if t.endswith("$function$"):
    t += ";"


def troca(velho, novo, quantas=1):
    global t
    assert t.count(velho) == quantas, "nao achei (%d x %d): %s" % (t.count(velho), quantas, velho[:70])
    t = t.replace(velho, novo)


# 1. uma variavel para o bairro parecido
troca("  v_livre  boolean;        -- procurar na cidade inteira (102)",
      "  v_livre  boolean;        -- procurar na cidade inteira (102)\n"
      "  v_perto  text;           -- o bairro parecido, quando ele escreve outro (105)")

# 2. o bloco inteiro de "nada aqui nem perto" trocado por um so
inicio = "  -- Nada aqui nem perto: quem responde e a funcao antiga"
fim = "  SELECT coalesce((SELECT i.bairro FROM imoveis i"
i, j = t.index(inicio), t.index(fim)

novo = """  -- NADA AQUI NEM PERTO (105, Tel 23/09: "nao e para ocorrer esse tipo de
  -- dupla busca, se eu coloco regra e para seguir").
  --
  -- Ate aqui, quando esta busca nao achava nada, quem respondia era a busca
  -- ANTIGA -- que nao conhece tipo, nem finalidade, nem faixa de teto. Era a
  -- unica porta por onde as regras dele nao passavam, e foi por ela que
  -- sairam dois apartamentos para quem pediu casa. Agora quem responde e
  -- aqui, com as mesmas regras do resto da funcao.
  IF v_aqui IS NULL AND v_alt IS NULL THEN

    -- 1. O BAIRRO EXISTE? Pode ser so o jeito de escrever.
    IF NOT v_livre AND NOT EXISTS (
         SELECT 1 FROM imoveis i
          WHERE nay_normalizar_lugar(i.bairro, true)
                LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%') THEN

      SELECT i.bairro INTO v_perto
        FROM imoveis i
       WHERE i.bairro IS NOT NULL AND btrim(i.bairro) <> ''
       GROUP BY i.bairro
       ORDER BY similarity(lower(unaccent(i.bairro)), lower(unaccent(coalesce(p_bairro, '')))) DESC
       LIMIT 1;

      IF v_perto IS NOT NULL
         AND similarity(lower(unaccent(v_perto)), lower(unaccent(coalesce(p_bairro, '')))) >= 0.45 THEN
        RETURN QUERY SELECT
          ('Você quis dizer ' || v_perto || '?')::text,
          ('o bairro que ele escreveu nao existe no catalogo, mas parece com este. '
           || 'Confirme com ele antes de procurar.')::text;
        RETURN;
      END IF;

      RETURN QUERY SELECT
        ('Não tenho imóvel nesse bairro. Em qual outro o cliente aceita?')::text,
        ('esse bairro nao esta no catalogo. NUNCA diga que nao trabalhamos em Manaus: '
         || 'a imobiliaria e de Manaus.')::text;
      RETURN;
    END IF;

    -- 2. O BAIRRO EXISTE, mas nao ha nada no perfil pedido. Dizer isso e a
    -- resposta certa -- trocar por outro tipo ou outro negocio nao e.
    RETURN QUERY SELECT
      (CASE WHEN v_livre
            THEN 'Não tenho ' || v_nada || ' nesse perfil disponível no momento.'
            ELSE 'No ' || initcap(btrim(coalesce(p_bairro, ''))) || ' não tenho ' || v_nada
                 || ' nesse perfil, nem nos bairros aqui perto.' END
       || CASE WHEN v_teto IS NULL
               THEN ' Me diz até que valor o cliente vai, que eu procuro em toda a cidade.'
               ELSE '' END)::text,
      ('nao existe nada no perfil pedido' || coalesce(' (' || v_rotulo || ')', '')
       || '. NAO ofereca outro tipo nem outra finalidade no lugar. Pergunte outro bairro '
       || 'ou outra faixa de preco.')::text;
    RETURN;
  END IF;

"""

t = t[:i] + novo + t[j:]

# a busca antiga nao pode ter sobrado em lugar nenhum desta funcao
assert "nay_buscar_por_perfil" not in t, "ainda sobrou chamada da busca antiga"

io.open(sys.argv[2], "w", encoding="utf-8", newline="\n").write(t + "\n")
print("105 montado: %d chars, sem a busca antiga" % len(t))
