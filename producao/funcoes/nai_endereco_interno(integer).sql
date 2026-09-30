CREATE OR REPLACE FUNCTION public.nai_endereco_interno(p_codigo integer)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT concat_ws(', ',
           nai_condominio_ok(i.condominio_nome),
           NULLIF(concat_ws(' ', NULLIF(i.logradouro,''), NULLIF(i.numero,'')), ''),
           NULLIF(i.complemento, ''),
           CASE WHEN coalesce(p.torre,'') <> '' THEN 'torre ' || p.torre END,
           CASE WHEN coalesce(p.unidade,'') <> '' THEN 'unidade ' || p.unidade END,
           NULLIF(i.bairro, ''))
         || ' (código ' || i.codigo || ')'
    FROM imoveis i LEFT JOIN imovel_privado p ON p.codigo = i.codigo
   WHERE i.codigo = p_codigo;
$function$;
