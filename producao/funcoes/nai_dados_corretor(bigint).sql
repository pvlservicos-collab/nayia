CREATE OR REPLACE FUNCTION public.nai_dados_corretor(p_contato bigint)
 RETURNS TABLE(primeiro_nome text, nome_completo text, cpf text, creci text, completo boolean)
 LANGUAGE sql
 STABLE
AS $function$
  WITH k AS (SELECT * FROM nai_contato WHERE id = p_contato),
       c AS (SELECT c.* FROM corretores c, k WHERE k.chave !~ '^lid:' AND nai_chave(c.telefone) = k.chave
              ORDER BY c.aprovado DESC LIMIT 1)
  SELECT coalesce(nay_nome_de_pessoa((SELECT nome FROM c)), nay_nome_de_pessoa(k.nome_completo),
                  nay_nome_de_pessoa(k.nome_whatsapp)),
         coalesce(k.nome_completo, nai_nome_completo((SELECT CASE WHEN nome_origem = 'manual' THEN nome END FROM c))),
         k.cpf,
         coalesce(NULLIF(btrim((SELECT creci FROM c)), ''), k.creci),
         (coalesce(k.nome_completo, nai_nome_completo((SELECT CASE WHEN nome_origem = 'manual' THEN nome END FROM c))) IS NOT NULL
          AND k.cpf IS NOT NULL
          AND coalesce(NULLIF(btrim((SELECT creci FROM c)), ''), k.creci) IS NOT NULL)
    FROM k;
$function$;
