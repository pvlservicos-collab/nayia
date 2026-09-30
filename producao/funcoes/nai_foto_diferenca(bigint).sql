CREATE OR REPLACE FUNCTION public.nai_foto_diferenca(p_foto bigint DEFAULT NULL::bigint)
 RETURNS TABLE(mudanca text, setor text, funcao text, args text, detalhe text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE v_foto bigint;
BEGIN
  v_foto := coalesce(p_foto, (SELECT max(id) FROM nai_foto));
  IF v_foto IS NULL THEN
    RETURN QUERY SELECT 'sem_foto'::text, NULL::text, NULL::text, NULL::text,
                        'nenhuma foto tirada ainda: rode nai_foto_tirar()'::text;
    RETURN;
  END IF;

  RETURN QUERY
  WITH antes AS (SELECT * FROM nai_funcao_foto WHERE foto_id = v_foto),
       agora AS (SELECT * FROM vw_nai_funcao_viva)
  -- corpo mudou: mesma assinatura, hash diferente. É o caso silencioso.
  SELECT 'corpo_mudou'::text, g.setor, g.funcao, g.args,
         ('era ' || a.tamanho || ' chars, agora ' || g.tamanho ||
          ' -- corrigida em producao e provavelmente nao voltou ao repositorio')::text
    FROM agora g JOIN antes a ON a.funcao = g.funcao AND a.args = g.args
   WHERE a.hash <> g.hash
  UNION ALL
  SELECT 'nova'::text, g.setor, g.funcao, g.args, 'nao existia na foto'::text
    FROM agora g
   WHERE NOT EXISTS (SELECT 1 FROM antes a WHERE a.funcao = g.funcao AND a.args = g.args)
  UNION ALL
  SELECT 'apagada'::text, a.setor, a.funcao, a.args, 'existia na foto e nao existe mais'::text
    FROM antes a
   WHERE NOT EXISTS (SELECT 1 FROM agora g WHERE g.funcao = a.funcao AND g.args = a.args)
  ORDER BY 1, 2, 3;
END;
$function$;
