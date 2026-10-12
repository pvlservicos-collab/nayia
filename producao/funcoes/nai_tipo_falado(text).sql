CREATE OR REPLACE FUNCTION public.nai_tipo_falado(p_tipo text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE p_tipo
           WHEN 'apartamento_condominio' THEN 'um apartamento em condomínio'
           -- apartamento sem condomínio: o próprio `tipo` desses imóveis já se
           -- chama "Apartamento em Via Pública", então é assim que ela fala
           WHEN 'apartamento_predio'     THEN 'um apartamento em via pública'
           WHEN 'casa_condominio'        THEN 'uma casa em condomínio'
           WHEN 'casa_rua'               THEN 'uma casa em via pública'
           WHEN 'sala_condominio'        THEN 'uma sala em condomínio'
           WHEN 'sala_rua'               THEN 'uma sala comercial'
           WHEN 'terreno_condominio'     THEN 'um lote em condomínio'
           WHEN 'terreno_rua'            THEN 'um terreno em via pública'
         END
$function$;
