CREATE OR REPLACE FUNCTION public.nai_e_resposta_aprovacao(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT lower(unaccent(btrim(coalesce(p, '')))) ~
         ('^(sim|s|ok|pode|pode seguir|segue|confirmad[oa]|confirmo|aprovad[oa]|aprovo|nao|nao pode|cancela|recuso)'
          || '[\s,.:#-]*(visita)?[\s#]*\d{0,6}[\s.!]*$')
      OR lower(unaccent(btrim(coalesce(p, '')))) ~ '^telefone\s+#?\d{1,6}\s+\S';
$function$
;
