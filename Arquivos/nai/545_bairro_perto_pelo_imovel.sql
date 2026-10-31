-- 545 (Pedro, 31/10/2026: "eu quero precisão nos bairros, dá um jeito aí"). Na revisão de 30/10, o "ao redor" trouxe
-- Tarumã para quem pediu Planalto, Compensa e Tarumã para Ponta Negra, Dom Pedro para Cidade Nova e o Tarumã inteiro
-- para Glória/Santo Antônio. A causa: o vizinho era o BAIRRO inteiro (o Tarumã tem 40 km² e o Tarumã-Açu 48, e fazem
-- divisa com meia cidade), ou um bairro a 3 km de centro a centro sem divisa, ou, sem vizinho conhecido, a zona toda.
--
-- Agora a medida é do IMÓVEL: a distância dele (imovel_geo, 231 dos 234 ofertáveis localizados) até a BORDA do bairro
-- pedido (os vértices do polígono de geo_bairro). "Aqui perto" = até 2 km da borda. O bairro do próprio imóvel vale 0.
--   geo_imovel_perto           (codigo, bairro, km) até 8 km; refeita pelo gatilho quando a localização muda
--   nay_imoveis_perto(b[], km) os imóveis a até km de algum dos bairros pedidos (fora deles), do mais perto
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS public.geo_imovel_perto (
  codigo integer NOT NULL,
  bairro text NOT NULL,          -- o nome de geo_bairro
  km     numeric(6,2) NOT NULL,  -- até a borda do bairro (0 = o bairro do próprio imóvel)
  PRIMARY KEY (codigo, bairro)
);
CREATE INDEX IF NOT EXISTS geo_imovel_perto_bairro ON public.geo_imovel_perto (bairro, km);
COMMENT ON TABLE public.geo_imovel_perto IS '545: distância de cada imóvel localizado (imovel_geo) até a borda de cada bairro (geo_bairro), até 8 km';

CREATE OR REPLACE FUNCTION public.geo_imovel_perto_refazer(p_codigo integer DEFAULT NULL)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_n integer;
BEGIN
  DELETE FROM geo_imovel_perto WHERE p_codigo IS NULL OR codigo = p_codigo;
  INSERT INTO geo_imovel_perto (codigo, bairro, km)
  SELECT g.codigo, b.bairro,
         CASE WHEN nay_normalizar_lugar(coalesce(i.bairro, g.bairro, ''), true) = nay_normalizar_lugar(b.bairro, true) THEN 0
              ELSE round(min(111.2 * sqrt(power((v.pt->>1)::float8 - g.lat, 2)
                                          + power(((v.pt->>0)::float8 - g.lon) * cos(radians(g.lat)), 2)))::numeric, 2) END
    FROM imovel_geo g
    LEFT JOIN imoveis i ON i.codigo = g.codigo
    JOIN geo_bairro b ON b.poligono IS NOT NULL AND abs(b.lat - g.lat) < 0.2 AND abs(b.lon - g.lon) < 0.2
    CROSS JOIN LATERAL jsonb_array_elements(b.poligono->'coordinates'->0) v(pt)
   WHERE (p_codigo IS NULL OR g.codigo = p_codigo) AND b.poligono->>'type' = 'Polygon'
   GROUP BY g.codigo, b.bairro, i.bairro, g.bairro
  HAVING nay_normalizar_lugar(coalesce(i.bairro, g.bairro, ''), true) = nay_normalizar_lugar(b.bairro, true)
      OR min(111.2 * sqrt(power((v.pt->>1)::float8 - g.lat, 2)
                          + power(((v.pt->>0)::float8 - g.lon) * cos(radians(g.lat)), 2))) <= 8;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END
$function$;

CREATE OR REPLACE FUNCTION public.geo_imovel_perto_gatilho()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM geo_imovel_perto_refazer(coalesce(NEW.codigo, OLD.codigo));
  RETURN NULL;
END
$function$;

DROP TRIGGER IF EXISTS imovel_geo_perto ON public.imovel_geo;
CREATE TRIGGER imovel_geo_perto AFTER INSERT OR UPDATE OF lat, lon, bairro OR DELETE ON public.imovel_geo
  FOR EACH ROW EXECUTE FUNCTION geo_imovel_perto_gatilho();

CREATE OR REPLACE FUNCTION public.nay_imoveis_perto(p_bairros text[], p_km numeric DEFAULT 2.0)
 RETURNS TABLE(codigo integer, km numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  -- os imóveis a até p_km da borda de algum dos bairros pedidos; os que ficam DENTRO de um deles não entram (são
  -- "no bairro", não "ao redor")
  WITH ped AS (SELECT DISTINCT nay_normalizar_lugar(b, true) AS n FROM unnest(p_bairros) b WHERE coalesce(btrim(b), '') <> '')
  SELECT p.codigo, min(p.km)
    FROM geo_imovel_perto p
   WHERE nay_normalizar_lugar(p.bairro, true) IN (SELECT n FROM ped) AND p.km <= p_km
     AND NOT EXISTS (SELECT 1 FROM geo_imovel_perto d WHERE d.codigo = p.codigo AND d.km = 0
                       AND nay_normalizar_lugar(d.bairro, true) IN (SELECT n FROM ped))
   GROUP BY p.codigo;
$function$;

GRANT SELECT ON public.geo_imovel_perto TO nay_core, nay_leitura;
GRANT EXECUTE ON FUNCTION public.nay_imoveis_perto(text[], numeric) TO nay_core, nay_leitura;

SELECT geo_imovel_perto_refazer() AS linhas;
COMMIT;
