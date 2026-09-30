-- 214 (revisão de 30/09/2026, pedido do Pedro: "revisa tudo ... a Nay desobedecer
-- regras ou esquecer do fluxo de identificação antes de mandar um imóvel").
-- Dois achados na conversa real do corretor …2954 (11:18 e 11:21):
--
-- 1. "MAS NO CASA EU TENHO ESTES DISPONÍVEIS". Ele perguntou da casa 5736
--    (indisponível); nai_status_do_imovel oferece "os disponíveis do mesmo
--    condomínio" -- e o condomínio de toda casa de rua é "Casa". Saíram TODAS as
--    casas da cidade, aluguel e venda misturados, sem filtro nenhum.
--    Agora: nome genérico (Casa, Apartamento, Sala, Terreno...) não é condomínio
--    -- cai na pergunta de sempre ("quer que eu veja mais opções? me informe os
--    bairros ou a faixa de preço"); e a lista é só do MESMO negócio do imóvel que
--    ele perguntou (aluguel com aluguel, venda com venda), até 8.
--
-- 2. O CORTE QUE VIRAVA SILÊNCIO. "Manda as de locação": o modelo quis mandar as
--    fotos do 5736 sem consultar; a parede saida_sem_consulta cortou as fotos e não
--    sobrou nada -- o corretor ficou sem resposta. Em 3 dias, 2 casos que pediam
--    resposta ("Cliente gostou do apto ... a compra é à vista"; "Manda as de
--    locação"); o resto era cortesia. Agora, se a parede cortou, nada saiu no turno
--    e a mensagem não é cortesia: nai_escalar_calado -- responde pela ficha quando
--    ele citou código, senão vai ao Tel (aviso + aba Tel, 24 h), como a regra 03.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.nai_status_do_imovel(p_codigo integer)
 RETURNS TABLE(texto_pronto text, disponivel boolean, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  i      record;
  v_card text;
  v_cond text;
  v_alt  text;
  v_n    int;
  v_situ text;
BEGIN
  SELECT im.codigo, im.status, im.bairro, nai_condominio_ok(im.condominio_nome) AS cond,
         im.valor_aluguel, im.valor_venda
    INTO i FROM imoveis im WHERE im.codigo = p_codigo;
  IF i.codigo IS NULL THEN
    RETURN QUERY SELECT ('Não achei o imóvel ' || p_codigo || '. Confere o código pra mim?')::text, false,
                        'mande o texto_pronto exatamente como veio.'::text;
    RETURN;
  END IF;

  IF nai_imovel_disponivel(p_codigo) THEN
    SELECT c.texto_pronto INTO v_card FROM nai_card_do_imovel(p_codigo) c;
    RETURN QUERY SELECT ('📌 Status: Disponível' || E'\n\n' || v_card)::text, true,
      ('mande o texto_pronto EXATAMENTE como veio: a linha de status e o card, com as quebras de linha. '
       || 'As fotos e a pergunta saem sozinhas atrás. Não escale.')::text;
    RETURN;
  END IF;

  v_situ := CASE WHEN i.status = 'Alugado' THEN 'está alugado' ELSE 'está indisponível' END;
  v_cond := nullif(btrim(coalesce(i.cond, '')), '');
  -- 214: "Casa" é o condomínio de toda casa de rua -- não é condomínio
  IF lower(unaccent(coalesce(v_cond, ''))) ~ '^(casas?|apartamentos?|apto|salas?( comerciais| comercial)?|terrenos?|lotes?|galpao|galpoes|ponto comercial|imove(l|is)|residencia|kitnet|studio|flat|chacaras?|sitios?|cobertura)$' THEN
    v_cond := NULL;
  END IF;

  IF v_cond IS NOT NULL THEN
    SELECT count(*),
           string_agg('• ' || y.codigo || ' — ' || coalesce(y.tipo, 'Imóvel')
                      || CASE WHEN coalesce(y.quartos, 0) > 0
                              THEN ', ' || y.quartos || CASE WHEN y.quartos = 1 THEN ' quarto' ELSE ' quartos' END ELSE '' END
                      || CASE WHEN coalesce(i.valor_aluguel, 0) > 0 AND coalesce(y.valor_aluguel, 0) > 0
                              THEN ', aluguel R$ ' || replace(to_char(y.valor_aluguel, 'FM999,999,990'), ',', '.')
                              WHEN coalesce(y.valor_venda, 0) > 0
                              THEN ', venda R$ ' || replace(to_char(y.valor_venda, 'FM999,999,990'), ',', '.')
                              WHEN coalesce(y.valor_aluguel, 0) > 0
                              THEN ', aluguel R$ ' || replace(to_char(y.valor_aluguel, 'FM999,999,990'), ',', '.') ELSE '' END,
                      E'\n' ORDER BY y.v)
      INTO v_n, v_alt
      FROM (SELECT x.*, CASE WHEN coalesce(i.valor_aluguel, 0) > 0 THEN x.valor_aluguel ELSE x.valor_venda END AS v
              FROM imoveis x
             WHERE x.codigo <> p_codigo
               AND NOT coalesce(x.e_parceiro, false)
               AND nai_condominio_ok(x.condominio_nome) = v_cond
               AND nai_imovel_disponivel(x.codigo)
               -- 214: o mesmo negócio do imóvel que ele perguntou
               AND CASE WHEN coalesce(i.valor_aluguel, 0) > 0 THEN coalesce(x.valor_aluguel, 0) > 0
                        WHEN coalesce(i.valor_venda, 0) > 0 THEN coalesce(x.valor_venda, 0) > 0
                        ELSE true END
             ORDER BY 2 LIMIT 8) y;
  END IF;

  IF coalesce(v_n, 0) > 0 THEN
    RETURN QUERY SELECT
      ('Hmmm, vi aqui que o ' || p_codigo || ' ' || v_situ || ' no momento. Mas no ' || v_cond
       || ' eu tenho ' || CASE WHEN v_n = 1 THEN 'este disponível' ELSE 'estes disponíveis' END || ':'
       || E'\n' || v_alt || E'\n\n'
       || CASE WHEN v_n = 1 THEN 'Quer que eu te mande as fotos dele?'
               ELSE 'Qual deles te interessa? Te mando as fotos.' END)::text,
      false,
      'mande o texto_pronto EXATAMENTE como veio. Não mande card nem fotos agora: elas saem quando ele escolher.'::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    ('Hmmm, vi aqui que o ' || p_codigo || ' ' || v_situ || ' no momento, quer que eu veja mais opções perto '
     || 'para o seu cliente? Basta me informar os bairros, ou a faixa de preço que eu já vejo aqui, ok?')::text,
    false,
    'mande o texto_pronto EXATAMENTE como veio. Não mande card nem fotos.'::text;
END;
$function$;

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  d text := pg_get_functiondef(p_fn);
  n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN
    RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 60);
  END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

SELECT pg_temp.trocar('nai_enfileirar_resposta_ferramentas(bigint,text,jsonb,text,jsonb,jsonb)',
$a$  v_r         jsonb;
BEGIN$a$,
$b$  v_r         jsonb;
  v_base      text;       -- 214
  v_papel     text;       -- 214
BEGIN$b$);

SELECT pg_temp.trocar('nai_enfileirar_resposta_ferramentas(bigint,text,jsonb,text,jsonb,jsonb)',
$a$  RETURN v_r;
END;
$function$$a$,
$b$  -- 214: A PAREDE CORTOU E NÃO SOBROU NADA. Sem isto o corretor ficava sem
  -- resposta ("Manda as de locação", "Cliente gostou do apto"). Cortesia continua
  -- sem resposta, de propósito.
  SELECT papel INTO v_papel FROM nai_turno WHERE id = p_turno;
  IF v_contato IS NOT NULL AND v_papel = 'corretor' AND v_tem_lista AND v_antes > 0
     AND NOT coalesce(v_consultou, false)
     AND NOT EXISTS (SELECT 1 FROM nai_saida s WHERE s.turno_id = p_turno)
     AND nullif(btrim(coalesce(p_escreveu, '')), '') IS NOT NULL
     AND NOT nai_e_so_cortesia(p_escreveu) THEN
    v_base := nai_escalar_calado(p_turno, p_escreveu, 'resposta cortada: ia mandar imóvel sem consultar', NULL);
    IF v_base IS NOT NULL THEN
      PERFORM nai_enfileirar_texto(p_turno, NULL, v_contato, 'turno', v_base, 'resposta', 1);
      PERFORM nai_anotar(p_turno, 24, 'corte_sem_silencio', 'mudou', 'a ficha respondeu no lugar do que foi cortado');
    ELSE
      PERFORM nai_anotar(p_turno, 24, 'corte_sem_silencio', 'parou', 'nada saiu depois do corte: foi ao Tel');
    END IF;
  END IF;

  RETURN v_r;
END;
$function$$b$);
COMMIT;
