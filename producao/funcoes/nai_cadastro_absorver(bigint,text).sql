CREATE OR REPLACE FUNCTION public.nai_cadastro_absorver(p_id bigint, p_texto text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE d jsonb; n int := 0;
BEGIN
  IF p_id IS NULL OR coalesce(btrim(p_texto), '') = '' THEN RETURN 0; END IF;
  d := nai_cadastro_ler(p_texto);
  IF d = '{}'::jsonb THEN RETURN 0; END IF;

  UPDATE nai_imovel_novo n2 SET
    area       = coalesce(n2.area,       (d->>'area')::numeric),
    quartos    = coalesce(n2.quartos,    (d->>'quartos')::int),
    suites     = coalesce(n2.suites,     (d->>'suites')::int),
    banheiros  = coalesce(n2.banheiros,  (d->>'banheiros')::int),
    vagas      = coalesce(n2.vagas,      (d->>'vagas')::int),
    mobilia    = coalesce(n2.mobilia,    d->>'mobilia'),
    valor      = coalesce(n2.valor,      (d->>'valor')::numeric),
    finalidade = coalesce(n2.finalidade, d->>'finalidade'),
    tipo       = coalesce(n2.tipo,       d->>'tipo')
   WHERE n2.id = p_id AND n2.situacao = 'colhendo';

  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$function$;
