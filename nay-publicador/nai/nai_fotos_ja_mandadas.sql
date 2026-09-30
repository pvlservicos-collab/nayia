CREATE OR REPLACE FUNCTION public.nai_fotos_ja_mandadas(p_contato bigint, p_codigo integer, p_horas integer DEFAULT 24)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM nai_saida s
     WHERE s.contato_id = p_contato
       AND s.codigo = p_codigo
       AND s.tipo = 'imagem'
       AND s.estado IN ('enviado', 'enviando', 'simulado')
       AND s.criado_em > now() - make_interval(hours => p_horas));
$function$
;
