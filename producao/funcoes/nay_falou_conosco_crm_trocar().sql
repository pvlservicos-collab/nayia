CREATE OR REPLACE FUNCTION public.nay_falou_conosco_crm_trocar()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM privado.falou_conosco_crm_tmp;
  IF n = 0 THEN RETURN 0; END IF;          -- cópia vazia = erro na leitura: mantém a de antes
  TRUNCATE privado.falou_conosco_crm;
  INSERT INTO privado.falou_conosco_crm SELECT * FROM privado.falou_conosco_crm_tmp;
  TRUNCATE privado.falou_conosco_crm_tmp;
  RETURN n;
END $function$;
