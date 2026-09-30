CREATE OR REPLACE FUNCTION public.nai_jev_decidiria(p_jev jsonb)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN coalesce((p_jev #>> '{cortesia,noul}')::real, 0)
         >= coalesce(nullif(nai_cfg('jev_piso_cortesia','0.70'),''),'0.70')::real
      THEN 'cortesia: segue com quem atendia'
    WHEN coalesce((p_jev #>> '{oferta,noul}')::real, 0)
         >= coalesce(nullif(nai_cfg('jev_piso_oferta','0.60'),''),'0.60')::real
      OR (p_jev #>> '{o_que_mandou,choice}') = 'anuncio_dele'
      THEN 'secretaria'
    WHEN (p_jev #>> '{atendente,choice}') = 'secretaria' THEN 'secretaria'
    ELSE 'locacao'
  END;
$function$
;
