CREATE OR REPLACE FUNCTION public.nai_so_cumprimentou(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- Tem que ser SO isso: "boa noite, tem apartamento?" nao entra aqui, porque
  -- ali ele ja disse a que veio.
  -- Uma ou mais saudacoes emendadas: "oi", "boa noite!", "ola, tudo bem?".
  -- Escrever cada combinacao a mao deixava "ola, tudo bem?" de fora.
  SELECT lower(unaccent(btrim(coalesce(p_texto, '')))) ~
         ('^((oi+|ola+|opa|eae|e ai|bom dia|boa tarde|boa noite|'
       || 'tudo bem|td bem|tudo bom|tudo certo|como vai|como esta|'
       -- o vocativo conta como parte do cumprimento: "Oi Nay" e so "oi"
       || 'nay|nay mendes|sra|sr|dona)'
       || '[\s,!.?]*)+$');
$function$
;
