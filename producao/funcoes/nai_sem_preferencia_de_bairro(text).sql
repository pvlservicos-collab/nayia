CREATE OR REPLACE FUNCTION public.nai_sem_preferencia_de_bairro(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT s ~ ('((nao|n) (tem|teria|ha|tenho|tem nenhuma) preferencia|'
           || 'sem preferencia|tanto faz|nao importa|indiferente|'
           || '(qualquer|todos os|todo) (bairro|lugar|regiao|local)|'
           || 'qualquer (um|uma)\M|'
           || '(nao|n) (tem|ha) (bairro|preferencia) (especifico|definido)|'
           || 'em qualquer|pode ser qualquer)')
    FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s) x;
$function$;
