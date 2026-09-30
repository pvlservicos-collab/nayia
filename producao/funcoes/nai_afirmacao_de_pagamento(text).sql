CREATE OR REPLACE FUNCTION public.nai_afirmacao_de_pagamento(p_frase text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- O que uma frase DA NAY afirma sobre pagamento. Pergunta não afirma nada.
  SELECT CASE
    WHEN q ~ '\?\s*$' THEN NULL
    WHEN q ~ '((somente|so|apenas|exclusivamente|unicamente)\s+(o\s+)?(pagamento\s+)?(a|e)\s+vista|so\s+aceita\s+(pagamento\s+)?a\s+vista|nao\s+(aceita|faz|pega|trabalha\s+com|tem|da\s+(pra|para))\s+(ser\s+)?financ|sem\s+financiamento|nao\s+(e\s+)?financiav)'
      THEN 'so_a_vista'
    WHEN q ~ '((aceita|faz|pega|pode\s+ser|da\s+(pra|para)|trabalha\s+com|tem)\s+(pagamento\s+)?((a\s+vista|avista)\s+(ou|e)\s+)?(ser\s+)?financ|financiavel|pode\s+financiar)'
      THEN 'financia'
    WHEN q ~ 'nao\s+aceita\s+(permuta|troca)' THEN 'permuta_nao'
    WHEN q ~ 'aceita\s+(permuta|troca)' THEN 'permuta_sim'
    WHEN q ~ 'fgts' THEN 'fgts'
  END
  FROM (SELECT lower(unaccent(coalesce(p_frase, ''))) AS q) x;
$function$;
