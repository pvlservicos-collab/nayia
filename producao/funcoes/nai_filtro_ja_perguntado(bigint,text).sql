CREATE OR REPLACE FUNCTION public.nai_filtro_ja_perguntado(p_contato bigint, p_qual text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  -- Cada pergunta do filtro sai uma vez por dia para a mesma pessoa (pelas
  -- duas linhas dela). Na segunda vez a busca segue sem ela: repetir a
  -- pergunta é o laço que a 102 e a 146 mataram.
  SELECT EXISTS (
    SELECT 1 FROM nai_saida s
     WHERE s.contato_id = ANY (nai_contato_irmaos(p_contato))
       AND s.tipo = 'texto' AND s.estado <> 'bloqueado'
       AND s.criado_em > now() - interval '24 hours'
       AND s.texto ~* CASE p_qual
             WHEN 'valor'    THEN 'at[ée] que valor'
             WHEN 'regiao'   THEN '(em qual bairro|qual regi[ãa]o|alguma regi[ãa]o|em qual outro)'
             WHEN 'abertura' THEN 'vou fazer um filtro com voc'
             ELSE '^$' END);
$function$;
