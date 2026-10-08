CREATE OR REPLACE FUNCTION public.crm_anuncio_mensagem(p jsonb, p_finalidade text DEFAULT NULL::text, p_agora timestamp with time zone DEFAULT now())
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hora    int := extract(hour FROM p_agora AT TIME ZONE 'America/Manaus');
  v_fam     text := coalesce(crm_anuncio_familia(p ->> 'tipo'), crm_anuncio_familia(p ->> 'titulo'));
  v_quartos numeric := crm_anuncio_numero(p -> 'quartos');
  v_veio    text := btrim(coalesce(p ->> 'bairro', ''));
  v_bairro  text;
  v_cliente text;
  v_msg     text;
BEGIN
  SELECT t.texto INTO v_msg FROM anuncio_abordagem_texto t WHERE t.chave = 'mensagem';
  SELECT t.texto INTO v_cliente FROM anuncio_abordagem_texto t
   WHERE t.chave = CASE WHEN v_fam = 'apartamento' AND v_quartos >= 3 THEN 'cliente_apartamento_grande'
                        WHEN v_fam = 'apartamento' THEN 'cliente_apartamento'
                        WHEN v_fam = 'casa' THEN 'cliente_casa'
                        WHEN v_fam = 'comercial' THEN 'cliente_comercial'
                        WHEN v_fam = 'terreno' THEN 'cliente_terreno'
                        ELSE 'cliente_outro' END;
  IF coalesce(btrim(v_msg), '') = '' OR coalesce(btrim(v_cliente), '') = '' THEN RETURN NULL; END IF;

  -- o bairro com o nome que o catálogo usa (o bot pode mandar "nossa-senhora-das-gracas");
  -- fora do catálogo, só se veio escrito como nome (com maiúscula, sem traço de endereço)
  IF v_veio <> '' THEN
    SELECT b.bairro INTO v_bairro FROM bairro_normal b WHERE b.normal = nay_normalizar_lugar(v_veio, true) LIMIT 1;
    IF v_bairro IS NULL AND v_veio ~ '^[A-ZÀ-Ý]' AND v_veio !~ '[-_/|,;:()0-9]' AND length(v_veio) BETWEEN 3 AND 40 THEN
      v_bairro := v_veio;
    END IF;
  END IF;

  v_msg := replace(v_msg, '{saudacao}', CASE WHEN v_hora BETWEEN 5 AND 11 THEN 'bom dia'
                                              WHEN v_hora BETWEEN 12 AND 17 THEN 'boa tarde' ELSE 'boa noite' END);
  v_msg := replace(v_msg, '{cliente}', btrim(v_cliente));
  v_msg := replace(v_msg, '{onde}', CASE WHEN v_bairro IS NOT NULL THEN 'na região de ' || v_bairro ELSE 'na sua região' END);
  v_msg := replace(v_msg, '{anunciando}', CASE WHEN p_finalidade = 'venda' THEN 'vendendo' ELSE 'anunciando' END);
  -- marcador que sobrou é texto quebrado: melhor não mandar nada
  IF v_msg ~ '[{}]' OR length(v_msg) < 80 THEN RETURN NULL; END IF;
  RETURN v_msg;
END
$function$;
