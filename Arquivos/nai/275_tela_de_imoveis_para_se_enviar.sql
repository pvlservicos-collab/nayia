-- 275 (02/10/2026): A TELA /imoveis, PARA O CORRETOR ACHAR E SE ENVIAR.
--
-- Pedro, 02/10: "implemente também a nova tela de enviar imóvel, vai ser um link /imoveis que vou
-- mandar para os corretores acharem os imóveis e se enviarem pelo WhatsApp... substitua as funções
-- lá pelas nossas mantendo o visual, mas deixando funcionando no nosso sistema."
--
-- O desenho é dele (Telaenviarmovel.html): mapa, busca, filtros, lista, selecionados e "Me envia".
-- O envio já existe (site_me_envia, 271). Faltava a lista: esta função devolve, de uma vez, os
-- imóveis que a Nay oferece -- nossos, Disponível, no site, sem bloqueio e com valor. Imóvel de
-- parceiro fica de fora: ele não pode ser enviado, então não entra numa tela que é para enviar.
--
-- O que NÃO sai daqui: rua, número, CEP, andar, unidade, dono. O ponto do mapa vai arredondado
-- (3 casas, ~110 m), igual à página do imóvel.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.site_imoveis_para_enviar()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH i AS (
    SELECT im.*,
           -- "Apartamento em Via Pública", "Casa" etc. no campo do condomínio são tipo, não nome
           CASE WHEN nay_sem_acento(lower(btrim(coalesce(im.condominio_nome, ''))))
                     ~ '^(casa|apartamento|sala|loja|galpao|terreno|lote|kitnet|flat|studio|cobertura|predio|ponto|sitio|chacara)'
                THEN NULL ELSE nullif(btrim(im.condominio_nome), '') END AS condo
      FROM imoveis im
     WHERE nay_esta_no_mercado(im.disponivel, im.bloqueado, im.publicado_no_site)
       AND NOT coalesce(im.e_parceiro, false)
       AND (coalesce(im.valor_venda, 0) > 0 OR coalesce(im.valor_aluguel, 0) > 0)
  ), t AS (
    SELECT i.*, coalesce(nullif(btrim(i.tipo), ''), 'Imóvel')
           || CASE WHEN coalesce(i.quartos, 0) > 0 THEN ' ' || i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END ELSE '' END
           || CASE WHEN i.condo IS NOT NULL THEN ' no ' || i.condo
                   WHEN nullif(btrim(i.bairro), '') IS NOT NULL THEN ' em ' || btrim(i.bairro) ELSE '' END AS titulo
      FROM i
  )
  SELECT coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'codigo', t.codigo,
           'tipo', coalesce(nullif(btrim(t.tipo), ''), 'Imóvel'),
           'titulo', t.titulo,
           'slug', btrim(regexp_replace(lower(nay_sem_acento(t.titulo)), '[^a-z0-9]+', '-', 'g'), '-'),
           'condominio', t.condo,
           'bairro', nullif(btrim(t.bairro), ''),
           'quartos', t.quartos, 'vagas', t.vagas,
           'area', round(coalesce(nullif(t.area_util, 0), nullif(t.area_total, 0))),
           'venda', nullif(t.valor_venda, 0), 'aluguel', nullif(t.valor_aluguel, 0),
           'foto', (SELECT f.url FROM imovel_fotos f
                     WHERE f.codigo = t.codigo AND coalesce(f.url, '') <> '' AND NOT coalesce(f.e_mosaico, false)
                     ORDER BY coalesce(f.e_capa, false) DESC, f.ordem NULLS LAST, f.id LIMIT 1),
           'lat', round(g.lat::numeric, 3), 'lon', round(g.lon::numeric, 3)))
         ORDER BY t.codigo DESC), '[]'::jsonb)
    FROM t LEFT JOIN imovel_geo g ON g.codigo = t.codigo;
$function$;

COMMENT ON FUNCTION public.site_imoveis_para_enviar() IS
  '275: os imóveis que a Nay oferece, para a tela /imoveis (o corretor acha e se envia). Sem rua, número, CEP, andar, unidade ou dono; ponto do mapa arredondado.';

REVOKE ALL ON FUNCTION public.site_imoveis_para_enviar() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_imoveis_para_enviar() TO nay_site_leitura, nay_site_escrita;

COMMIT;
