#!/usr/bin/env python3
"""191 -- remenda as funções VIVAS (pg_proc) para lerem a ficha do anúncio, e
imprime 191p_remendos.sql. Ver o cabeçalho de 191_ficha_completa.sql.

    python3 191_remendos.py > /tmp/191p.sql
"""
import subprocess, sys


def viva(nome):
    q = f"SELECT pg_get_functiondef('{nome}'::regproc)"
    return subprocess.run(['docker', 'exec', 'nay-postgres', 'psql', '-U', 'nay', '-d', 'naydb', '-At', '-c', q],
                          check=True, capture_output=True, text=True).stdout.rstrip('\n')


def troca(txt, velho, novo, nome):
    n = txt.count(velho)
    if n != 1:
        sys.exit(f'{nome}: trecho aparece {n} vezes (esperado 1): {velho[:100]!r}')
    return txt.replace(velho, novo)


out = ['-- 191p -- gerado por 191_remendos.py a partir do pg_proc vivo (29/09/2026).',
       'BEGIN;', "SET LOCAL lock_timeout = '5s';", '']

# ------------------------------------------------------- a resposta da base
f = viva('nai_resposta_da_base')
f = troca(f, "  n      int;\nBEGIN",
          "  n      int;\n  v_fin  text;   -- 191: a ficha do anuncio\n  v_per  text;\n  v_gar  text;\n  v_esc  text;\n  v_tx   text;\nBEGIN", 'base')
f = troca(f, "  car   := lower(unaccent(coalesce(array_to_string(i.caracteristicas, ', '), '') || ', ' || coalesce(i.extras->>'caracteristicas', '')));\n"
             "  dorig := coalesce(nay_descricao_segura(i.descricao), '');\n",
          "  -- 191: a FICHA DO ANUNCIO entra aqui -- caracteristicas do imovel e do\n"
          "  -- condominio, descricao e observacoes (sem numero de unidade). Antes era so\n"
          "  -- o banco, e 117 dos 260 imoveis no ar nao tinham descricao nenhuma.\n"
          "  car   := lower(unaccent(array_to_string(nai_ficha_caracteristicas(p_codigo), ', ')));\n"
          "  dorig := coalesce(nai_ficha_texto_livre(p_codigo), '');\n", 'base')
f = troca(f, "  v_inc := lower(unaccent(coalesce(i.extras->>'incluso no aluguel', '')));",
          "  v_inc := lower(unaccent(coalesce(nai_ficha_valor(p_codigo, 'incluso no aluguel'), '')));  -- 191", 'base')
# taxa e IPTU: a coluna, e na falta dela o valor escrito no anuncio
f = troca(f, "    ELSIF coalesce(i.taxa_condominio, 0) > 0 THEN\n"
             "      r := r || ('a taxa de condomínio é R$ ' || replace(to_char(i.taxa_condominio, 'FM999,999,990'), ',', '.'));\n    END IF;",
          "    ELSIF coalesce(i.taxa_condominio, 0) > 0 THEN\n"
          "      r := r || ('a taxa de condomínio é R$ ' || replace(to_char(i.taxa_condominio, 'FM999,999,990'), ',', '.'));\n"
          "    ELSIF nai_ficha_valor(p_codigo, 'taxa de condominio') ~ '\\d' THEN  -- 191\n"
          "      v_tx := regexp_replace(regexp_replace(nai_ficha_valor(p_codigo, 'taxa de condominio'), '\\s+', ' ', 'g'), ',00$', '');\n"
          "      r := r || ('a taxa de condomínio é ' || v_tx);\n    END IF;", 'base')
f = troca(f, "    ELSIF coalesce(i.iptu, 0) > 0 THEN\n"
             "      r := r || ('o IPTU é R$ ' || replace(to_char(i.iptu, 'FM999,999,990'), ',', '.'));\n    END IF;",
          "    ELSIF coalesce(i.iptu, 0) > 0 THEN\n"
          "      r := r || ('o IPTU é R$ ' || replace(to_char(i.iptu, 'FM999,999,990'), ',', '.'));\n"
          "    ELSIF nai_ficha_valor(p_codigo, 'iptu') ~ '\\d' THEN  -- 191\n"
          "      v_tx := regexp_replace(regexp_replace(nai_ficha_valor(p_codigo, 'iptu'), '\\s+', ' ', 'g'), ',00$', '');\n"
          "      r := r || ('o IPTU é ' || v_tx);\n    END IF;", 'base')
velho_fin = ("  -- FINANCIAMENTO (venda)\n"
             "  IF q ~ 'financ' AND coalesce(i.valor_venda, 0) > 0 THEN\n"
             "    IF coalesce(i.extras->>'aceita financiamento', '') ~* '^s' THEN r := r || 'aceita financiamento'::text;\n"
             "    ELSIF coalesce(i.extras->>'aceita financiamento', '') ~* '^n' THEN r := r || 'não aceita financiamento'::text; END IF;\n"
             "  END IF;\n")
novo_fin = """  -- FORMA DE PAGAMENTO (191, 29/09): SO A FICHA RESPONDE. A Nay disse ao Paulo
  -- que o Living Comfort (5664) era "somente a vista"; o anuncio diz "Aceita
  -- Financiamento? Sim". Aqui a pergunta de financiamento, de "e a vista?" e de
  -- forma de pagamento sai da linha do anuncio. Sem a linha, NULL: a
  -- ferramenta manda escalar ao Tel, e ninguem supoe.
  v_fin := nai_ficha_valor(p_codigo, 'aceita financiamento');
  IF q ~ '(financ|a vista|avista|forma de pagamento|\\mpagamento|\\mparcel)' AND coalesce(i.valor_venda, 0) > 0 THEN
    IF v_fin ~* '^s' THEN
      r := r || CASE WHEN q ~ '(a vista|avista)' THEN 'não precisa ser à vista: aceita financiamento'
                     ELSE 'aceita financiamento' END;
    ELSIF v_fin ~* '^n' THEN
      r := r || 'não aceita financiamento, é só à vista'::text;
    END IF;
  END IF;
  -- FGTS: so quando o anuncio fala (a frase dele)
  IF q ~ 'fgts' THEN
    v_fr := (regexp_match(dorig, '[^.!?\\n]*fgts[^.!?\\n]*', 'i'))[1];
    IF coalesce(btrim(v_fr), '') <> '' THEN r := r || ('sobre FGTS, o anúncio diz: "' || btrim(v_fr) || '"'); END IF;
  END IF;
  -- PERMUTA
  IF q ~ '(permuta|\\mtroca\\M)' THEN
    v_per := nai_ficha_valor(p_codigo, 'aceita permuta');
    IF v_per ~* '^s' THEN
      r := r || ('aceita permuta' || coalesce(' (' || lower(nai_ficha_valor(p_codigo, 'permuta')) || ')', ''));
    ELSIF v_per ~* '^n' THEN
      r := r || 'não aceita permuta'::text;
    END IF;
  END IF;
  -- GARANTIA DO ALUGUEL (fiador, caucao, seguro-fianca)
  IF q ~ '(fiador|caucao|garantia|seguro.?fianca|titulo de capitaliza|deposito)' AND coalesce(i.valor_aluguel, 0) > 0 THEN
    v_gar := nai_ficha_valor(p_codigo, 'garantia de aluguel');
    IF v_gar IS NOT NULL THEN r := r || ('a garantia do aluguel é ' || lower(v_gar)); END IF;
  END IF;
  -- LANCES DE ESCADA
  IF q ~ '(escada|lances)' THEN
    v_esc := nai_ficha_valor(p_codigo, 'lances de escada');
    IF v_esc ~ '\\d' THEN r := r || ('tem ' || v_esc || CASE WHEN v_esc = '1' THEN ' lance de escada' ELSE ' lances de escada' END); END IF;
  END IF;
"""
f = troca(f, velho_fin, novo_fin, 'base')
out.append(f + ';\n')

# ------------------------------------------------------------ a ferramenta
f = viva('nai_o_que_sei_do_imovel')
f = troca(f, "  v_base text;\nBEGIN",
          "  v_base text;\n  v_velho record;  -- 191\n  v_ass   text;\n  v_ficha text;\nBEGIN", 'ferramenta')
f = troca(f, "  RETURN QUERY SELECT x.texto_pronto, x.sabe, x.instrucao_para_voce FROM nay_o_que_sei_do_imovel(p_codigo, p_pergunta) x;",
"""  -- 191: o que o Tel ja respondeu deste imovel (a busca antiga) vem primeiro.
  SELECT x.texto_pronto, x.sabe, x.instrucao_para_voce INTO v_velho
    FROM nay_o_que_sei_do_imovel(p_codigo, p_pergunta) x LIMIT 1;
  IF coalesce(v_velho.sabe, false) THEN
    RETURN QUERY SELECT v_velho.texto_pronto, v_velho.sabe, v_velho.instrucao_para_voce;
    RETURN;
  END IF;
  -- ASSUNTO SENSIVEL QUE A FICHA NAO RESPONDE -> O TEL (Pedro, 29/09: "se nao
  -- tiver la claro, ela vai perguntar ao Tel e nao informar algo assim de forma
  -- errada"). Forma de pagamento, FGTS, permuta, garantia, documentacao, pet.
  v_ass := nai_assunto_sensivel(p_pergunta);
  IF v_ass IS NOT NULL AND length(v_cod) BETWEEN 3 AND 5 THEN
    RETURN QUERY SELECT NULL::text, false,
      ('ASSUNTO SENSIVEL (' || v_ass || ') QUE A FICHA DO ' || v_cod || ' NAO RESPONDE. NAO responda, NAO suponha, '
       || 'NAO diga "acho", "normalmente" nem "somente a vista": chame escalar_ao_tel com a pergunta dele e responda '
       || 'SILENCIO. O Tel responde e a resposta chega a ele.')::text;
    RETURN;
  END IF;
  -- O RESTO: A FICHA INTEIRA PARA LER (o "rag" do Pedro). Responder so com o
  -- que esta escrito; o que nao esta, sobe ao Tel.
  v_ficha := CASE WHEN length(v_cod) BETWEEN 3 AND 5 THEN nai_ficha_completa(v_cod::int) END;
  RETURN QUERY SELECT v_velho.texto_pronto, v_velho.sabe,
    (coalesce(v_velho.instrucao_para_voce, '')
     || CASE WHEN v_ficha IS NOT NULL
             THEN E'\\n\\nA FICHA INTEIRA DO IMOVEL -- leia antes de responder e responda SO com o que esta escrito nela. '
                  || E'O que nao esta escrito: chame escalar_ao_tel e responda SILENCIO.\\n' || v_ficha
             ELSE '' END)::text;""", 'ferramenta')
out.append(f + ';\n')

# ---------------------------------------------------------------- o card
f = viva('nai_card_do_imovel')
f = troca(f, 'CREATE OR REPLACE FUNCTION public.nai_card_do_imovel(p_codigo integer)',
          'CREATE OR REPLACE FUNCTION public.nai_card_do_banco(p_codigo integer)', 'card')
out.append("-- o card montado do banco, como era ate a 191: vira a reserva do card da ficha")
out.append(f + ';\n')
out.append("""CREATE OR REPLACE FUNCTION public.nai_card_do_imovel(p_codigo integer)
 RETURNS TABLE(texto_pronto text, qtd_fotos integer)
 LANGUAGE sql
 STABLE
AS $function$
  -- 191: O CARD DOS GRUPOS (Pedro, 29/09: "o card precisa ser ajustado"). O card
  -- dos grupos e montado pelo publicador lendo o anuncio -- traz lances de
  -- escada, caracteristicas, "aceita financiamento" e a OBS do Tel. O da Nay era
  -- remontado do banco, que nao tem nada disso. Agora a Nay manda o MESMO card,
  -- lido na ficha (ficha_do_anuncio.py), enquanto ele for recente e o preco
  -- bater com o banco. Senao, o card do banco, como sempre.
  SELECT coalesce(
           (SELECT f.card FROM imovel_ficha f JOIN imoveis i ON i.codigo = f.codigo
             WHERE f.codigo = p_codigo AND f.encontrado AND f.erro IS NULL AND f.card IS NOT NULL
               AND f.lido_em > now() - interval '26 hours'
               AND NOT coalesce(i.e_parceiro, false)
               AND coalesce(f.valor_venda, 0) = coalesce(i.valor_venda, 0)
               AND coalesce(f.valor_aluguel, 0) = coalesce(i.valor_aluguel, 0)
               AND f.card ~ ('C[óo]digo:\\s*' || p_codigo || '\\s*$')),
           b.texto_pronto),
         b.qtd_fotos
    FROM nai_card_do_banco(p_codigo) b;
$function$;
""")

# ------------------------------------------------------------ a conferência
f = viva('nai_conferir_resposta')
f = troca(f, "  v_fichas text;\nBEGIN", "  v_fichas text;\n  v_pg     record;  -- 191\nBEGIN", 'conferir')
f = troca(f, "  -- 06 ------------------------------------------------------------- SILÊNCIO",
"""  -- 05p ------------------------------ FORMA DE PAGAMENTO SO COM A FICHA (191)
  -- A Nay disse ao Paulo que o Living Comfort (5664) era "somente a vista", e
  -- depois confirmou quando ele repetiu. O anuncio diz que aceita financiamento.
  -- Toda frase dela que afirma forma de pagamento e conferida com a ficha do
  -- imovel de que fala: contradiz -> vira a frase certa; a ficha nao diz -> a
  -- frase sai e, se ele perguntou disso, o Tel e chamado.
  IF v_corretor AND NOT v_calada AND v_texto ~* nai_re_pagamento() THEN
    SELECT * INTO v_pg FROM nai_conferir_pagamento(v_texto, v_alvo);
    IF v_pg.trocas > 0 THEN
      v_texto := v_pg.texto;
      v_guarda := coalesce(v_guarda || '+', '') || 'pagamento_da_ficha';
      PERFORM nai_anotar(p_turno, 5, 'pagamento_da_ficha', 'mudou', 'afirmacao de pagamento corrigida pela ficha');
    END IF;
    IF coalesce(array_length(v_pg.sem_dado, 1), 0) > 0 THEN
      v_texto := v_pg.texto;
      IF nai_assunto_sensivel(coalesce(p_escreveu, '')) IN ('pagamento', 'fgts', 'permuta') OR btrim(v_texto) = '' THEN
        v_base := nai_escalar_calado(p_turno, p_escreveu, 'forma de pagamento que a ficha nao diz',
                                     (SELECT c FROM unnest(v_pg.sem_dado) c WHERE c > 0 LIMIT 1));
        IF v_base IS NULL THEN
          PERFORM nai_anotar(p_turno, 5, 'pagamento_da_ficha', 'parou', 'a ficha nao diz: subiu ao Tel e parou o chat');
          RETURN jsonb_build_object('acao', 'parou', 'guarda', 'pagamento_sem_ficha_foi_ao_tel');
        END IF;
        v_texto := v_base;
      END IF;
      v_guarda := coalesce(v_guarda || '+', '') || 'pagamento_sem_ficha';
      PERFORM nai_anotar(p_turno, 5, 'pagamento_da_ficha', 'mudou', 'afirmacao sem ficha tirada: '
                         || array_to_string(v_pg.sem_dado, ', '));
    END IF;
  END IF;

  -- 06 ------------------------------------------------------------- SILÊNCIO""", 'conferir')
out.append(f + ';\n')

# ------------------------------------------------------------- a bateria
f = viva('nai_rodar_casos')
anc = "      WHEN 'pelo_nome'  THEN nai_imovel_pelo_condominio(c.frase, '')::text  -- 190\n"
f = troca(f, anc, anc +
          "      WHEN 'afirma_pagamento' THEN coalesce(nai_afirmacao_de_pagamento(c.frase), '-')  -- 191\n"
          "      WHEN 'assunto_sensivel' THEN coalesce(nai_assunto_sensivel(c.frase), '-')  -- 191\n", 'casos')
out.append(f + ';\n')
out.append("""INSERT INTO nai_caso (quando, quem, frase, pergunta, esperado, regra, ativo) VALUES
 ('2026-09-29', 'Paulo 29/09', 'Já o Living Comfort 5664 é somente à vista.', 'afirma_pagamento', 'so_a_vista', 'afirmar "somente à vista" é conferido com a ficha', true),
 ('2026-09-29', 'Paulo 29/09', 'Certo, Paulo! O Living Comfort é somente à vista mesmo.', 'afirma_pagamento', 'so_a_vista', 'confirmar o erro do corretor também é afirmar', true),
 ('2026-09-29', 'Paulo 29/09', 'A casa 1360 aceita pagamento à vista ou financiado.', 'afirma_pagamento', 'financia', 'aceita financiamento é conferido com a ficha', true),
 ('2026-09-29', 'regra 191', 'Esse não aceita financiamento.', 'afirma_pagamento', 'so_a_vista', 'negar financiamento é afirmar à vista', true),
 ('2026-09-29', 'regra 191', 'Aceita financiamento?', 'afirma_pagamento', '-', 'pergunta não afirma nada', true),
 ('2026-09-29', 'regra 191', 'Aceita FGTS na entrada?', 'assunto_sensivel', 'fgts', 'FGTS só com a ficha ou o Tel', true),
 ('2026-09-29', 'regra 191', 'Pode ser financiado?', 'assunto_sensivel', 'pagamento', 'financiamento só com a ficha ou o Tel', true),
 ('2026-09-29', 'regra 191', 'O proprietário aceita um carro como parte?', 'assunto_sensivel', 'permuta', 'permuta só com a ficha ou o Tel', true),
 ('2026-09-29', 'regra 191', 'O condomínio tem piscina?', 'assunto_sensivel', '-', 'lazer não é assunto sensível: a ficha responde', true);
""")
out.append('COMMIT;\n')
print('\n'.join(out))
