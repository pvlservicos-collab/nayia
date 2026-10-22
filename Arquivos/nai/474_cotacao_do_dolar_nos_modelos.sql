-- 474 -- A cotação do dólar para a página admin › Modelos mostrar os gastos em reais
--
-- Pedro, 22/10/2026: "põe o valor lá no painel de modelos em reais principalmente, e dólar pequenininho em cinza, nós
-- usamos reais aqui". A OpenAI cobra em dólar (o custo de ia_uso e do core_trace é US$); a página converte pela cotação
-- guardada aqui, que a rota /admin/api/modelos renova quando passa de 12 h (Frankfurter, BCE; reserva AwesomeAPI).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.ia_cotacao (
  moeda         text PRIMARY KEY,
  brl           numeric NOT NULL,
  fonte         text,
  atualizado_em timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE privado.ia_cotacao IS '474: quanto vale 1 unidade da moeda em reais (a página Modelos converte US$ -> R$).';
INSERT INTO privado.ia_cotacao (moeda, brl, fonte) VALUES ('USD', 5.049, 'Frankfurter (BCE), 22/10/2026')
ON CONFLICT (moeda) DO NOTHING;

CREATE OR REPLACE FUNCTION public.site_ia_cotacao_salvar(p_brl numeric, p_fonte text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_brl IS NULL OR p_brl < 1 OR p_brl > 20 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'cotação fora do razoável');
  END IF;
  INSERT INTO privado.ia_cotacao (moeda, brl, fonte, atualizado_em) VALUES ('USD', p_brl, left(p_fonte, 120), now())
  ON CONFLICT (moeda) DO UPDATE SET brl = EXCLUDED.brl, fonte = EXCLUDED.fonte, atualizado_em = now();
  RETURN jsonb_build_object('ok', true, 'brl', p_brl);
END $function$;

CREATE OR REPLACE FUNCTION public.site_ia_cotacao()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT coalesce((SELECT jsonb_build_object('usd_brl', c.brl, 'fonte', c.fonte,
                                             'atualizado_em', to_char(c.atualizado_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI'),
                                             'horas', round(extract(epoch FROM now() - c.atualizado_em) / 3600, 1))
                     FROM privado.ia_cotacao c WHERE c.moeda = 'USD'), '{}'::jsonb)
$function$;

GRANT EXECUTE ON FUNCTION public.site_ia_cotacao() TO nay, nay_site_leitura, nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.site_ia_cotacao_salvar(numeric, text) TO nay, nay_site_escrita;

COMMIT;
