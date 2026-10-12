CREATE OR REPLACE FUNCTION public.nai_tipo_preciso(p_codigo integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
           WHEN i.tipo ~* 'apartamento|flat|cobertura|studio|kitnet|loft'
             THEN CASE WHEN cond THEN 'apartamento_condominio' ELSE 'apartamento_predio' END
           WHEN i.tipo ~* 'sala|loja|ponto|conjunto|escrit'
             THEN CASE WHEN cond THEN 'sala_condominio' ELSE 'sala_rua' END
           WHEN i.tipo ~* 'casa|chacara|sitio|fazenda|sobrado'
             THEN CASE WHEN cond THEN 'casa_condominio' ELSE 'casa_rua' END
           WHEN i.tipo ~* 'lote|terreno'
             THEN CASE WHEN cond THEN 'terreno_condominio' ELSE 'terreno_rua' END
           ELSE 'outro'
         END
    FROM imoveis i,
         LATERAL (SELECT nay_condominio_de_verdade(i.tipo, i.condominio_nome) IS NOT NULL) AS c(cond)
   WHERE i.codigo = p_codigo;
$function$;
