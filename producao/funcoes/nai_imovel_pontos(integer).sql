CREATE OR REPLACE FUNCTION public.nai_imovel_pontos(p_codigo integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  i          imoveis;
  v_fotos    int;
  v_incluso  text;
  v_condo    boolean;      -- está em condomínio?
  v_vertical boolean;      -- tem andar (apartamento, flat, cobertura, sala)
  v_aluga    boolean;
  pontos     numeric := 0;
  total      numeric := 0;
  falta      text[] := '{}';
  falta_ess  text[] := '{}';
  -- campo, peso, preenchido, se_aplica, bloco
  r          record;
BEGIN
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL THEN RETURN NULL; END IF;
  SELECT count(*) INTO v_fotos FROM imovel_fotos f WHERE f.codigo = p_codigo;
  v_incluso  := lower(unaccent(coalesce(i.extras->>'incluso no aluguel', '')));
  v_condo    := coalesce(btrim(i.condominio_nome), '') <> ''
                AND lower(unaccent(btrim(i.condominio_nome))) !~ '^(casa|casa de condominio|apartamento|apartamento em via publica|sala/andar|sala|loja|loja/ponto|galpao/deposito|lote|lote em condominio|flat|cobertura|predio|terreno|condominio nao identificado)$';
  v_vertical := coalesce(i.tipo, '') ~* '^(apartamento|flat|cobertura|sala|kitnet|studio)';
  v_aluga    := coalesce(i.valor_aluguel, 0) > 0;

  FOR r IN
    SELECT * FROM (VALUES
      -- essencial (50)
      ('tipo',              8, coalesce(btrim(i.tipo), '') <> '',                                   true,                'essencial'),
      ('bairro',            8, coalesce(btrim(i.bairro), '') <> '',                                 true,                'essencial'),
      ('valor',             8, coalesce(i.valor_venda, 0) > 0 OR coalesce(i.valor_aluguel, 0) > 0,  true,                'essencial'),
      ('quartos',           6, i.quartos IS NOT NULL,                                               coalesce(i.tipo,'') !~* '^(lote|terreno|galp|loja|sala|pr)', 'essencial'),
      ('área',              6, coalesce(i.area_util, 0) > 0 OR coalesce(i.area_total, 0) > 0,        true,                'essencial'),
      ('fotos',             8, v_fotos > 0,                                                         true,                'essencial'),
      ('proprietário',      6, i.proprietario_id IS NOT NULL,                                       true,                'essencial'),
      -- importante (35)
      ('banheiros',         4, i.banheiros IS NOT NULL,                                             coalesce(i.tipo,'') !~* '^(lote|terreno)', 'importante'),
      ('vagas',             4, i.vagas IS NOT NULL,                                                  coalesce(i.tipo,'') !~* '^(lote|terreno)', 'importante'),
      ('mobília',           5, coalesce(btrim(i.mobilia), '') <> '',                                 v_aluga AND coalesce(i.tipo,'') ~* '^(apartamento|casa|flat|cobertura|kitnet|studio)', 'importante'),
      ('condomínio',        4, v_condo,                                                              coalesce(i.tipo,'') ~* 'condomin|^(apartamento|flat|cobertura)', 'importante'),
      ('endereço',          4, coalesce(btrim(i.logradouro), '') <> '',                              true,                'importante'),
      ('características',   6, coalesce(cardinality(i.caracteristicas), 0) > 0,                      true,                'importante'),
      ('descrição',         4, coalesce(btrim(i.descricao), '') <> '',                               true,                'importante'),
      ('taxa de condomínio',4, i.taxa_condominio IS NOT NULL OR v_incluso ~ 'condom',                v_condo AND v_aluga, 'importante'),
      -- detalhe (15)
      ('suítes',            3, i.suites IS NOT NULL,                                                 coalesce(i.tipo,'') !~* '^(lote|terreno|galp|loja|sala)', 'detalhe'),
      ('sol',               3, coalesce(btrim(i.sol), '') <> '',                                     true,                'detalhe'),
      ('IPTU',              3, i.iptu IS NOT NULL OR v_incluso ~ 'iptu',                              true,                'detalhe'),
      ('vagas cobertas',    3, i.vagas_cobertas IS NOT NULL,                                          coalesce(i.tipo,'') !~* '^(lote|terreno)', 'detalhe')
    ) AS t(campo, peso, tem, aplica, bloco)
  LOOP
    CONTINUE WHEN NOT r.aplica;
    total := total + r.peso;
    IF r.tem THEN
      pontos := pontos + r.peso;
    ELSE
      falta := falta || r.campo;
      IF r.bloco = 'essencial' THEN falta_ess := falta_ess || r.campo; END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'codigo', p_codigo,
    'pontos', pontos, 'de', total,
    'pct', CASE WHEN total > 0 THEN round(100 * pontos / total) ELSE 0 END,
    'falta', to_jsonb(falta),
    'falta_essencial', to_jsonb(falta_ess));
END;
$function$;
