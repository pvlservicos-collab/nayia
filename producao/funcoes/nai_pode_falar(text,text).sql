CREATE OR REPLACE FUNCTION public.nai_pode_falar(p_chave text, p_telefone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  WITH alvo AS (
    SELECT coalesce(
             (SELECT nai_chave(i.telefone) FROM identidade_lid i
               WHERE p_chave ~ '^lid:'
                 -- 193: o grupo grava o LID so com digitos e o webhook manda
                 -- "<digitos>@lid". Compara sem o sufixo, nos dois formatos.
                 AND i.lid IN (regexp_replace(p_telefone, '@lid$', ''),
                               regexp_replace(p_telefone, '@lid$', '') || '@lid')
               LIMIT 1),
             p_chave) AS chave
  )
  SELECT NOT EXISTS (SELECT 1 FROM nai_corretor_pergunta q, alvo
                      WHERE q.chave = alvo.chave AND q.decisao = 'nao')
     AND EXISTS (SELECT 1 FROM corretores c, alvo
                  WHERE nai_chave(c.telefone) = alvo.chave
                    AND c.pode_falar AND c.ativo);
$function$;
