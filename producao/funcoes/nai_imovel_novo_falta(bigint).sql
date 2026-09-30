CREATE OR REPLACE FUNCTION public.nai_imovel_novo_falta(p_id bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- A ordem e a do modelo que o Tel mandou em 26/09. `tipo` saiu da fila:
  -- ele se deduz do texto e o modelo dele nem pergunta.
  SELECT CASE
    WHEN coalesce(n.condominio, n.bairro) IS NULL THEN 'lugar'
    WHEN n.bairro     IS NULL THEN 'bairro'
    WHEN n.area       IS NULL THEN 'tamanho'
    WHEN n.quartos    IS NULL THEN 'comodos'
    WHEN n.banheiros  IS NULL THEN 'banheiros'
    WHEN n.vagas      IS NULL THEN 'vagas'
    WHEN n.mobilia    IS NULL THEN 'mobilia'
    WHEN n.valor      IS NULL OR n.finalidade IS NULL THEN 'preco'
    WHEN NOT EXISTS (SELECT 1 FROM nai_imovel_novo_foto f WHERE f.novo_id = n.id) THEN 'fotos'
  END
  FROM nai_imovel_novo n WHERE n.id = p_id;
$function$;
