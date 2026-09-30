CREATE OR REPLACE FUNCTION public.nai_pergunta_de_imovel(p_texto text, p_telefone text, p_codigo_citado integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT p_codigo_citado IS NOT NULL
      OR nai_assunto_de_corretor(p_texto)
      OR coalesce((nai_pedido_de_perfil(p_texto)->>'e_pedido')::boolean, false)
      OR nai_pede_foto(p_texto)
      OR coalesce(array_length(nai_imovel_pelo_condominio(p_texto, p_telefone), 1), 0) > 0
      OR EXISTS (SELECT 1 FROM unnest(coalesce(nay_codigos_citados(coalesce(p_texto, '')), '{}'::text[])) x
                  WHERE x ~ '^[0-9]{3,5}$');
$function$;
