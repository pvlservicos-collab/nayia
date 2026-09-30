CREATE OR REPLACE FUNCTION public.nai_disparo_conferir(p_telefone text, p_codigo integer, p_quem text)
 RETURNS TABLE(pode boolean, motivo text, card text, fotos text[])
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  i     imoveis;
  v_ja  timestamptz;
  v_ch  text := nai_chave(regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g'));
BEGIN
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL THEN
    RETURN QUERY SELECT false, 'não achei esse código'::text, NULL::text, NULL::text[]; RETURN;
  END IF;
  IF coalesce(i.e_parceiro, false) THEN
    RETURN QUERY SELECT false, 'é imóvel de parceiro (parceria não sai)'::text, NULL::text, NULL::text[]; RETURN;
  END IF;
  IF NOT nai_imovel_disponivel(p_codigo) THEN
    RETURN QUERY SELECT false, ('está ' || lower(coalesce(i.status, 'indisponível')) || ', não mandei')::text, NULL::text, NULL::text[]; RETURN;
  END IF;
  IF v_ch IS NULL THEN
    RETURN QUERY SELECT false, 'número inválido'::text, NULL::text, NULL::text[]; RETURN;
  END IF;
  v_ja := nay_reservar_imovel_do_dia(v_ch, p_codigo, 'disparo', NULL);
  IF v_ja IS NOT NULL THEN
    RETURN QUERY SELECT false, ('as fotos já foram para esse número ' || nay_quando_foi(v_ja)
                                || ' (libera ' || nay_quando_foi(v_ja + interval '24 hours') || ')')::text,
                        NULL::text, NULL::text[];
    RETURN;
  END IF;
  RETURN QUERY
    SELECT true, NULL::text,
           (SELECT c.texto_pronto FROM nai_card_do_imovel(p_codigo) c),
           (SELECT coalesce(array_agg(f.url), '{}') FROM nai_imagens_do_envio(p_codigo) f WHERE NOT f.e_colagem);
END;
$function$;
