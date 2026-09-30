CREATE OR REPLACE FUNCTION public.nay_captacao_campos_desconhecidos(p_campos jsonb)
 RETURNS text[]
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(array_agg(k ORDER BY k), ARRAY[]::text[])
    FROM jsonb_object_keys(coalesce(p_campos, '{}'::jsonb)) AS k
   WHERE k NOT IN (SELECT column_name::text
                     FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'imoveis')
     -- NOSSOS, não do site: campo que a plataforma usa e que NÃO vai para o
     -- imobeasy.com. Sem esta exceção a função acusa um campo que a própria
     -- tela criou, e o Tel vê "campo inventado" para a anotação que ele
     -- mesmo escreveu.
     AND k NOT IN ('anotacoes');
$function$;
