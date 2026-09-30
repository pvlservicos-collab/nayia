CREATE OR REPLACE FUNCTION public.nai_sec_guardar_do_imovel(p_turno bigint, p_tipo text DEFAULT NULL::text, p_finalidade text DEFAULT NULL::text, p_condominio text DEFAULT NULL::text, p_bairro text DEFAULT NULL::text, p_quartos text DEFAULT NULL::text, p_suites text DEFAULT NULL::text, p_vagas text DEFAULT NULL::text, p_area text DEFAULT NULL::text, p_valor text DEFAULT NULL::text, p_taxa text DEFAULT NULL::text, p_mobilia text DEFAULT NULL::text, p_descricao text DEFAULT NULL::text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; v_id bigint; v_falta text; v_num text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT n.id INTO v_id FROM nai_imovel_novo n
   WHERE n.contato_id = t.contato_id AND n.situacao = 'colhendo'
   ORDER BY n.id DESC LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO nai_imovel_novo (contato_id, turno_id) VALUES (t.contato_id, p_turno)
      RETURNING id INTO v_id;
  END IF;

  -- O PRIMEIRO numero, nao todos colados. "3 quartos sendo 1 suite" com
  -- `regexp_replace` virava 31 quartos -- medido no primeiro teste.
  v_num := '\d+';
  UPDATE nai_imovel_novo n SET
    -- TIPO SO SE FOR UM TIPO (112): "apartamentos, casas e imoveis em
    -- predios" nao e tipo, e foi isso que virou imovel em 23/09.
    tipo       = coalesce(nai_tipo_canonico(p_tipo), n.tipo),
    -- a finalidade tambem sai do VALOR: acima de 100 mil e venda (98).
    finalidade = coalesce(nay_negocio_pedido(concat_ws(' ', p_finalidade, p_valor)), n.finalidade),
    -- UM NOME SO (112): "Living Comfort e Coral Gables" sao dois.
    condominio = coalesce(CASE WHEN nai_um_nome_so(p_condominio) THEN btrim(p_condominio) END, n.condominio),
    bairro     = coalesce(CASE WHEN nai_um_nome_so(p_bairro) THEN btrim(p_bairro) END, n.bairro),
    quartos    = coalesce((regexp_match(coalesce(p_quartos, ''), v_num))[1]::int, n.quartos),
    suites     = coalesce((regexp_match(coalesce(p_suites, ''), v_num))[1]::int, n.suites),
    vagas      = coalesce((regexp_match(coalesce(p_vagas, ''), v_num))[1]::int, n.vagas),
    area       = coalesce((regexp_match(coalesce(p_area, ''), v_num))[1]::numeric, n.area),
    -- acima de 100 milhoes nao e imovel, e engano de digitacao (112)
    valor      = coalesce(nullif(least(coalesce(nay_maior_valor(p_valor),
                                              nay_valor_em_reais(p_valor)), 100000000), 100000000), n.valor),
    taxa_condominio = coalesce(nay_valor_em_reais(p_taxa), n.taxa_condominio),
    mobilia    = coalesce(nullif(btrim(coalesce(p_mobilia, '')), ''), n.mobilia),
    descricao  = coalesce(nullif(btrim(concat_ws(E'\n', n.descricao, nullif(btrim(coalesce(p_descricao, '')), ''))), ''), n.descricao)
   WHERE n.id = v_id;

  v_falta := nai_imovel_novo_falta(v_id);
  IF v_falta IS NULL THEN
    -- SOBE SOZINHO (Tel, 22/09: "so tira o contato do corretor e pode subir
    -- automatico"). O codigo sai aqui e fica na ficha.
    PERFORM nai_imovel_novo_subir(v_id);
    PERFORM nai_anotar(p_turno, 6, 'cadastro_completo', 'mudou',
                       'ficha ' || v_id || ' virou o imovel '
                       || coalesce((SELECT codigo::text FROM nai_imovel_novo WHERE id = v_id), '?'));
    RETURN QUERY SELECT 'Obrigada! Já deixei registrado aqui.'::text,
      ('a ficha fechou e o imovel entrou no sistema. Agradeca e encerre. NAO diga codigo, '
       || 'nao fale de comissao e nao prometa quando ele vai ao ar.')::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT nai_imovel_novo_pergunta(v_falta),
    ('ficha ' || v_id || '. Diga SO essa pergunta, sem juntar outra.')::text;
END;
$function$;
