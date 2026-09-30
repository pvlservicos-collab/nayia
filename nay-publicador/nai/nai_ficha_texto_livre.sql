CREATE OR REPLACE FUNCTION public.nai_ficha_texto_livre(p_codigo integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- Descrição + observações, do banco ou do anúncio, SEM número de unidade
  -- (`nay_descricao_segura`, a mesma raspagem de sempre).
  SELECT nullif(btrim(concat_ws(E'\n',
           nay_descricao_segura(coalesce(nullif(btrim(i.descricao), ''), f.descricao)),
           nay_descricao_segura(f.observacoes))), '')
    FROM imoveis i LEFT JOIN imovel_ficha f ON f.codigo = i.codigo AND f.encontrado
   WHERE i.codigo = p_codigo;
$function$
;
