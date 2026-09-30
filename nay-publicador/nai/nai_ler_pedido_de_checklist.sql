CREATE OR REPLACE FUNCTION public.nai_ler_pedido_de_checklist(p text)
 RETURNS TABLE(telefone text, tipo text)
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  s      text := lower(unaccent(btrim(coalesce(p, ''))));
  v_fone text := '(?:55[\s.-]*)?\(?[0-9]{2}\)?[\s.-]*[0-9]{4,5}[\s.-]*[0-9]{4}';
  m      text[];
BEGIN
  IF s !~ '(che(ck|k|c|q)u?e?[\s-]*li?st|lista\s+de\s+documentos|check\s*-?\s*list)' THEN
    RETURN;
  END IF;
  -- é pedido de envio, não conversa: curto, e com verbo de mandar, número, ou
  -- começando pela palavra do checklist
  IF length(s) > 160 OR (s !~ '(envi|mand|repass|encaminh)' AND s !~ v_fone
                         AND s !~ '^(@?nay[\s,;:.!-]*)?(o\s+|a\s+)?(che(ck|k|c|q)u?e?[\s-]*li?st|lista\s+de\s+documentos)') THEN
    RETURN;
  END IF;
  m := regexp_match(s, '(' || v_fone || ')');
  RETURN QUERY SELECT
    CASE WHEN m IS NOT NULL THEN m[1] END,
    CASE WHEN s ~ '(alug|loca[cç]|inquilin|locat)' AND s !~ '(vend|compr)' THEN 'locacao'
         WHEN s ~ '(vend|compr)' AND s !~ '(alug|loca[cç]|inquilin|locat)' THEN 'venda' END;
END;
$function$
;
