CREATE OR REPLACE FUNCTION public.nai_e_resposta_automatica(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT length(btrim(coalesce(p_texto, ''))) >= 20
     AND lower(unaccent(p_texto)) ~ ('(estou ausente|retornarei (o |seu |o seu )?contato|retornarei em breve'
         || '|responderei (assim que|com toda|em breve)|logo retorno o contato|assim que possivel,? eu retorno'
         || '|recebi sua mensagem|mensagem automatica|resposta automatica'
         || '|(agradece|agradecemos) (o |seu )?contato|atend(emos|imento) de segunda)')
     AND cardinality(nay_codigos_citados(p_texto)) = 0;
$function$;
