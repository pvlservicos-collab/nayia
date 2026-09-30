CREATE OR REPLACE FUNCTION public.nay_primeiro_nome(nome text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT NULLIF(btrim(
    -- 4. so letras
    regexp_replace(
      -- 3. primeiro token
      split_part(
        btrim(
          -- 2. tira o tratamento que ja vem embutido no nome
          regexp_replace(
            -- 1. tira invisiveis e pontuacao de borda
            regexp_replace(coalesce(nome, ''), '[​-‏‪-‮﻿]', '', 'g'),
            '^\s*(sr\.?|sra\.?|dr\.?|dra\.?|dona|exmo\.?|exma\.?)\s+', '', 'i')
        ), ' ', 1),
      '[^A-Za-zÀ-ÿ]', '', 'g')
  ), '');
$function$;
