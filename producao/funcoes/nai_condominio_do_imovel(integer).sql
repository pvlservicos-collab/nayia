CREATE OR REPLACE FUNCTION public.nai_condominio_do_imovel(p_codigo integer)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT to_jsonb(f) - 'ia_sugestao' - 'ia_em' - 'campos_google' - 'site_antigo_id'
    --  ^ `campos_google` e `ia_sugestao` FICAM FORA: procedência e sugestão são
    --    ferramenta de revisão do Tel. Para ela o dado vem do mesmo lugar que
    --    os outros -- regra dele, 11/10.
    FROM imoveis i
    LEFT JOIN condominios c
           ON c.id = i.condo_id
           OR (i.condo_id IS NULL
               AND lower(unaccent(btrim(c.nome))) = lower(unaccent(btrim(i.condominio_nome))))
    JOIN condominio_ficha f ON f.condominio_id = c.id
   WHERE i.codigo = p_codigo
     AND nay_condominio_de_verdade(i.tipo, i.condominio_nome) IS NOT NULL
   ORDER BY (c.id = i.condo_id) DESC NULLS LAST
   LIMIT 1;
$function$;
