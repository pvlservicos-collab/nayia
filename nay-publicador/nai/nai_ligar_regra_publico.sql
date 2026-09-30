CREATE OR REPLACE FUNCTION public.nai_ligar_regra_publico()
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE v_desde text;
BEGIN
  v_desde := nullif(btrim(nai_cfg('regra_publico_desde', '')), '');
  IF v_desde IS NULL THEN
    v_desde := to_char(now(), 'YYYY-MM-DD HH24:MI:SSOF');
    UPDATE nai_config SET valor = v_desde WHERE chave = 'regra_publico_desde';
  END IF;
  UPDATE nai_config SET valor = 'sim' WHERE chave = 'regra_publico';
  RETURN 'Regra ligada. Quem tem mensagem anterior a ' || v_desde ||
         ' e conversa antiga (Nay calada, menos pedindo foto de imovel).';
END;
$function$
;
