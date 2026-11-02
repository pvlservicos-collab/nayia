DO $t$
DECLARE r jsonb; n int;
BEGIN
  r := crm_esteira_automatica(7);
  ASSERT jsonb_typeof(r) = 'array', 'array';
  ASSERT jsonb_array_length(r) >= 2, 'ao menos as duas filas sem data';
  RAISE NOTICE 'itens: %, por origem: %', jsonb_array_length(r),
    (SELECT jsonb_object_agg(o, c) FROM (SELECT x->>'origem' o, count(*) c FROM jsonb_array_elements(r) x GROUP BY 1) q);
  RAISE NOTICE 'amostra: %', (SELECT x FROM jsonb_array_elements(r) x WHERE x->>'origem' = 'parceria_dia_seguinte' LIMIT 1);
END $t$;
