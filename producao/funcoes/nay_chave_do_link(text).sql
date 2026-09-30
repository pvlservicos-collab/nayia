CREATE OR REPLACE FUNCTION public.nay_chave_do_link(p_link text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  WITH sem_cauda AS (
    -- Fora tudo depois de '?' ou '#' (utm_source, gclid, xtmc): muda a cada
    -- compartilhamento e é o mesmo anúncio. E fora a barra final.
    SELECT regexp_replace(
             split_part(split_part(btrim(coalesce(p_link, '')), '#', 1), '?', 1),
             '/+$', '') AS t
  ), normal AS (
    -- `lower` ANTES de tirar o protocolo, e não depois: `^https?://` é
    -- sensível a caixa, e o teclado do celular manda a primeira letra da
    -- mensagem em maiúscula -- "Https://am.olx.com.br/...". Com a ordem
    -- invertida o protocolo não era removido e o MESMO endereço gerava duas
    -- chaves (medido em 02/09). Só mordia o caminho `url:`, o de link sem id;
    -- quando há id, o número do fim salva a comparação.
    SELECT regexp_replace(lower(t), '^https?://(www\.)?', '') AS t FROM sem_cauda
  )
  SELECT CASE
           WHEN t = '' THEN NULL
           -- O id do anúncio é o último grupo de 8 ou mais dígitos do
           -- caminho (ex.: .../casa-no-parque-das-laranjeiras-1526572128).
           -- Oito é o piso: CEP tem 8 e nunca fica no fim do slug, e
           -- número de casa no slug tem 1 a 4.
           ELSE coalesce('olx:' || substring(t from '(\d{8,})$'), 'url:' || t)
         END
    FROM normal;
$function$;
