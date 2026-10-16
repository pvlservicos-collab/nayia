CREATE OR REPLACE FUNCTION public.site_olx_anuncio_pedir(p_codigo integer, p_negocio text, p_campos jsonb, p_quem text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  m   jsonb := olx_anuncio_montar(p_codigo, p_negocio);
  a   jsonb;
  c   jsonb := coalesce(p_campos, '{}'::jsonb);
  v   text;
  fts jsonb;
  id_ bigint;
BEGIN
  IF p_negocio NOT IN ('venda', 'locacao') THEN RAISE EXCEPTION 'negócio inválido: %', p_negocio; END IF;
  IF NOT coalesce((m->>'ok')::boolean, false) THEN
    RAISE EXCEPTION 'não dá para anunciar: %', coalesce(m->>'barrado',
      (SELECT string_agg(x, '; ') FROM jsonb_array_elements_text(coalesce(m->'falta', '[]'::jsonb)) x), 'o anúncio não monta');
  END IF;
  IF EXISTS (SELECT 1 FROM privado.olx_anuncio_pedido WHERE codigo = p_codigo AND negocio = p_negocio
                AND estado IN ('pendente', 'enviando')) THEN
    RAISE EXCEPTION 'já tem um pedido deste anúncio sendo enviado';
  END IF;
  a := m->'anuncio';
  -- só o que a pessoa pode mexer no popup: título, descrição, preço, CEP e as fotos (as nossas, na ordem dela)
  v := btrim(coalesce(c->>'subject', ''));
  IF v <> '' THEN a := jsonb_set(a, '{subject}', to_jsonb(left(v, 90))); END IF;
  v := btrim(coalesce(c->>'body', ''));
  IF v <> '' THEN a := jsonb_set(a, '{body}', to_jsonb(left(v, 6000))); END IF;
  v := regexp_replace(coalesce(c->>'price', ''), '[^0-9]', '', 'g');
  IF v <> '' THEN
    IF v::numeric < 100 THEN RAISE EXCEPTION 'preço inválido'; END IF;
    a := jsonb_set(a, '{price}', to_jsonb(v::numeric));
  END IF;
  v := regexp_replace(coalesce(c->>'zipcode', ''), '[^0-9]', '', 'g');
  IF v <> '' THEN
    IF length(v) <> 8 THEN RAISE EXCEPTION 'CEP inválido'; END IF;
    a := jsonb_set(a, '{zipcode}', to_jsonb(v));
  END IF;
  IF jsonb_typeof(c->'images') = 'array' THEN
    SELECT coalesce(jsonb_agg(u ORDER BY n), '[]'::jsonb) INTO fts
      FROM jsonb_array_elements_text(c->'images') WITH ORDINALITY x(u, n)
     WHERE u ~ '^https://' AND n <= 20;
    IF jsonb_array_length(fts) = 0 THEN RAISE EXCEPTION 'o anúncio precisa de pelo menos uma foto'; END IF;
    a := jsonb_set(a, '{images}', fts);
  END IF;
  a := jsonb_set(a, '{operation}', '"insert"');
  INSERT INTO privado.olx_anuncio_pedido (codigo, negocio, conta, anuncio, hash, ad_id, pedido_por)
  VALUES (p_codigo, p_negocio,
          coalesce(nullif((SELECT valor FROM privado.olx_config WHERE chave = 'conta_que_publica'), ''), 'proprietarios'),
          a, m->>'hash', m->>'ad_id', left(coalesce(p_quem, ''), 80))
  RETURNING id INTO id_;
  RETURN id_;
END
$function$;
