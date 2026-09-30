CREATE OR REPLACE FUNCTION public.nai_vocativo(p_nome text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- SEM SR. E SRA. (Tel, 28/09/2026): "só cita o nome do corretor, porque os
  -- nomes no BR variam muito". Até aqui vinha "Sr./Sra." + primeiro nome, com
  -- o gênero adivinhado pelo nome. O resto continua: sem nome de verdade
  -- (til, número, emoji, nome de empresa), não chama de nada.
  SELECT CASE
    WHEN coalesce(btrim(p_nome), '') = '' THEN NULL
    WHEN btrim(p_nome) !~ '[[:alpha:]]{2}' THEN NULL
    WHEN nay_primeiro_nome(p_nome) IS NOT NULL AND nay_primeiro_nome(p_nome) ~ '[[:alpha:]]{2}'
      THEN nay_primeiro_nome(p_nome)
    ELSE NULL
  END;
$function$;
