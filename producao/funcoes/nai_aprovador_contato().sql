CREATE OR REPLACE FUNCTION public.nai_aprovador_contato()
 RETURNS bigint
 LANGUAGE sql
AS $function$
  SELECT CASE WHEN nai_chave(nai_cfg('aprovador_visita_telefone', '')) IS NOT NULL
              THEN nai_contato_do_cadastro(nai_cfg('aprovador_visita_telefone', ''), nai_cfg('aprovador_visita_nome', 'Rayssa')) END;
$function$;
