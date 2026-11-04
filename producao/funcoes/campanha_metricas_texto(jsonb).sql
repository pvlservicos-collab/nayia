CREATE OR REPLACE FUNCTION public.campanha_metricas_texto(p_m jsonb)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT 'O ' || (p_m->>'codigo') || ' ' || campanha_lista_texto(array_remove(ARRAY[
           CASE WHEN p_m->>'desde' IS NOT NULL
                THEN CASE WHEN (p_m->>'no_site')::boolean THEN 'está no nosso site desde ' ELSE 'está cadastrado conosco desde ' END
                     || campanha_mes((p_m->>'desde')::date) END,
           CASE WHEN (p_m->>'chaves_na_mao')::boolean THEN 'no portal Chaves na Mão' END,
           CASE WHEN (p_m->>'posts')::int > 0
                THEN 'já foi divulgado ' || (p_m->>'posts') || CASE WHEN (p_m->>'posts')::int = 1 THEN ' vez' ELSE ' vezes' END
                     || ' em ' || (p_m->>'grupos') || CASE WHEN (p_m->>'grupos')::int = 1 THEN ' grupo' ELSE ' grupos' END
                     || ' de corretores'
                     || CASE WHEN (p_m->>'corretores')::int >= 20
                             THEN ', para mais de ' || ((p_m->>'corretores')::int / 10 * 10) || ' corretores' ELSE '' END END,
           CASE WHEN (p_m->>'clientes')::int > 0
                THEN 'foi apresentado a ' || (p_m->>'clientes') || CASE WHEN (p_m->>'clientes')::int = 1 THEN ' cliente' ELSE ' clientes' END END
         ], NULL)) || '.'
$function$;
