-- 413: PARCEIROS ANTIGOS ficam fora do que a Nay de captação oferece aos leads (19/10/2026)
--
-- Pedro: "sobre os imóveis disparados pela lista de captação, não quero os imóveis antigos, só os imóveis novos que o
-- Tel cadastrou (9049, 9050, 9051...), só esses novos com parceria; os antigos viram a tag Parceiros antigos, vou fazer
-- um disparo para atualizar o status deles antes de podermos oferecer; põe esse filtro na Nay captação que eu tinha
-- liberado para mandar eles para os leads".
--
-- O que é "antigo": os imóveis de parceiro que vieram do site antigo (origem 'site', importados em 10 e 21/08/2026,
-- parceiro pelo captador). Os novos do Tel têm a marca à mão (extras.parceiro_manual = 'sim', 400) e nasceram em
-- outubro. A marca mora em extras.parceiro_antigo = 'sim'; sai pela chave "Parceiro antigo" no editar (ou quando o
-- disparo de atualização confirmar o status, no passo seguinte dele).
--
-- Quem deixa de ver os antigos: a Nay do WhatsApp dos clientes da OLX/orgânicos (nay-olx), nos dois portões da 400:
--   olx_cliente_buscar (a busca por perfil, ramo aceita_parceiro) e olx_imovel_vai_ao_cliente (o código citado/escolhido,
--   que o Python chama em _ofertavel). O envio à mão pela equipe (CRM, "Enviar imóvel") não muda: é gente decidindo.
-- A tela do admin (lista, filtro Situação > Parceiros antigos, editar) lê imovel_parceiro_antigo(codigo).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.imovel_parceiro_antigo(p_codigo integer)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
  -- 413: parceiro do site antigo, ainda sem o status atualizado pelo disparo: a Nay de captação não oferece
  SELECT coalesce((SELECT coalesce(i.extras->>'parceiro_antigo', '') = 'sim' FROM imoveis i WHERE i.codigo = p_codigo), false)
$function$;
COMMENT ON FUNCTION public.imovel_parceiro_antigo(integer) IS
  '413: extras.parceiro_antigo = sim (parceiro importado do site antigo, status por atualizar). Fora da Nay de captação.';
GRANT EXECUTE ON FUNCTION public.imovel_parceiro_antigo(integer) TO nay_site_leitura, nay_site_escrita;

CREATE OR REPLACE FUNCTION public.olx_imovel_vai_ao_cliente(p_codigo integer, p_telefone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (SELECT 1 FROM core_imovel_busca b WHERE b.codigo = p_codigo AND b.ofertavel)
      OR (EXISTS (SELECT 1 FROM imoveis i
                   WHERE i.codigo = p_codigo AND i.e_parceiro AND i.status = 'Disponível'
                     AND coalesce(i.disponivel, true) AND NOT coalesce(i.bloqueado, false)
                     AND (coalesce(i.valor_aluguel, 0) > 0 OR coalesce(i.valor_venda, 0) > 0)
                     -- 413: parceiro ANTIGO (do site antigo) não sai até o disparo atualizar o status
                     AND coalesce(i.extras->>'parceiro_antigo', '') <> 'sim')
          AND olx_pode_receber_parceiro(p_telefone))
$function$;

CREATE OR REPLACE FUNCTION public.olx_cliente_buscar(p_filtros jsonb, p_excluir integer[] DEFAULT '{}'::integer[], p_limite integer DEFAULT 5)
 RETURNS TABLE(codigo integer, bairro text, condominio text, tipo text, quartos integer, preco numeric, perto boolean)
 LANGUAGE sql
 STABLE
AS $function$
  WITH f0 AS (
    SELECT CASE WHEN lower(coalesce(p_filtros->>'finalidade', '')) LIKE 'vend%' THEN 'venda' ELSE 'locacao' END AS fin,
           lower(unaccent(coalesce(p_filtros->>'tipo', ''))) AS tipo,
           CASE WHEN coalesce(p_filtros->>'teto', '') ~ '^[0-9]+(\.[0-9]+)?$' THEN (p_filtros->>'teto')::numeric END AS teto,
           CASE WHEN coalesce(p_filtros->>'quartos', '') ~ '^[0-9]+$' THEN (p_filtros->>'quartos')::int END AS quartos,
           coalesce(p_filtros->>'aceita_menos_quartos', '') = 'true' AS menos,
           lower(coalesce(p_filtros->>'mobilia', '')) AS mob,
           lower(coalesce(p_filtros->>'financiamento', '')) ~ '(financ|simula|aprovad)' AS financia,
           -- 394: "não serve escada" (a pergunta da venda até 500 mil)
           coalesce(p_filtros->>'aceita_escada', '') = 'false' AS sem_escada
  ), f AS (
    SELECT f0.*, f0.tipo IN ('galpao', 'predio', 'sala', 'loja', 'terreno', 'comercial') AS comercial FROM f0
  ), pedidos AS (     -- os bairros que ela disse, no nome do cadastro ("pq 10" -> parque 10 de novembro)
    -- 388: o nome do cadastro parecido; senão o bairro do conjunto/lugar (nai_bairros_do_lugar: "Vieiralves")
    SELECT DISTINCT nay_normalizar_lugar(x, true) AS n
      -- 394: "qualquer bairro" vale (antes os bairros ditos antes continuavam mandando)
      FROM jsonb_array_elements_text(CASE WHEN coalesce(p_filtros->>'qualquer_bairro', '') = 'true' THEN '[]'::jsonb
                                          WHEN jsonb_typeof(p_filtros->'bairros') = 'array' THEN p_filtros->'bairros'
                                          ELSE '[]'::jsonb END) b
      CROSS JOIN LATERAL unnest(coalesce(CASE WHEN nay_bairro_parecido(b) IS NOT NULL THEN ARRAY[nay_bairro_parecido(b)] END,
                                         nullif(nai_bairros_do_lugar('no ' || b), '{}'), ARRAY[b])) x
     WHERE btrim(b) <> ''
  ), perto AS (
    SELECT DISTINCT nay_normalizar_lugar(x, true) AS n
      FROM unnest(nai_bairros_ao_redor(ARRAY(SELECT n FROM pedidos))) x
     WHERE nay_normalizar_lugar(x, true) NOT IN (SELECT n FROM pedidos)
  ), c AS (
    SELECT i.codigo, i.bairro, i.condominio_nome, i.tipo, i.quartos, nay_normalizar_lugar(i.bairro, true) AS bn,
           CASE WHEN f.fin = 'venda' THEN i.valor_venda ELSE i.valor_aluguel END AS p
      FROM core_imovel_busca i CROSS JOIN f
      LEFT JOIN imoveis x ON x.codigo = i.codigo
     -- 400: o imóvel de parceiro Disponível vai ao cliente final (o nay-olx só manda aceita_parceiro a quem não é corretor)
     -- 413: o parceiro ANTIGO (do site antigo, extras.parceiro_antigo = sim) fica fora até o disparo atualizar o status
     WHERE (i.ofertavel
            OR (coalesce(p_filtros->>'aceita_parceiro', '') = 'true' AND coalesce(i.e_parceiro, false)
                AND x.status = 'Disponível' AND coalesce(x.disponivel, true) AND NOT coalesce(x.bloqueado, false)
                AND coalesce(x.extras->>'parceiro_antigo', '') <> 'sim'))
       AND CASE WHEN f.fin = 'venda' THEN i.de_venda ELSE i.de_locacao END
       AND CASE WHEN f.tipo IN ('', 'tanto_faz') THEN i.tipo IN ('apartamento', 'casa', 'casa_condominio', 'flat', 'cobertura')
                WHEN f.tipo = 'casa' THEN i.tipo IN ('casa', 'casa_condominio')
                -- 392: galpão e prédio moram em 'outro' na busca; o cadastro diz qual
                WHEN f.tipo = 'galpao' THEN i.tipo = 'outro' AND lower(unaccent(coalesce(x.tipo, ''))) LIKE 'galp%'
                WHEN f.tipo = 'predio' THEN i.tipo = 'outro' AND lower(unaccent(coalesce(x.tipo, ''))) LIKE 'predio%'
                WHEN f.tipo = 'comercial' THEN i.tipo IN ('sala', 'loja')
                                          OR (i.tipo = 'outro' AND lower(unaccent(coalesce(x.tipo, ''))) ~ '^(galp|predio)')
                ELSE i.tipo = f.tipo END
       AND (f.comercial OR f.quartos IS NULL OR coalesce(i.quartos, 0) >= f.quartos - CASE WHEN f.menos THEN 1 ELSE 0 END)
       -- 388: "modulados e ar" (semi) também aceita o mobiliado; mobiliado é só mobiliado. 392: no comercial não conta
       -- 394: mobília é coisa de LOCAÇÃO (o Felipe, venda até 900 mil "mobiliada": a busca voltava vazia)
       AND (f.comercial OR f.fin = 'venda' OR f.mob NOT IN ('mobiliado', 'semi') OR i.mobilia = f.mob
            OR (f.mob = 'semi' AND i.mobilia = 'mobiliado'))
       AND NOT (f.sem_escada AND i.tipo IN ('apartamento', 'cobertura', 'flat') AND nai_imovel_tem_elevador(i.codigo) IS FALSE)
       AND NOT (i.codigo = ANY (coalesce(p_excluir, '{}')))
       -- quem vai financiar não recebe imóvel que não aceita financiamento (a regra dos pedidos dos grupos, 371)
       AND NOT (f.fin = 'venda' AND f.financia AND lower(coalesce(x.extras->>'aceita financiamento', '')) LIKE 'n%')
  )
  SELECT c.codigo, c.bairro, c.condominio_nome, c.tipo, c.quartos, c.p, (c.bn IN (SELECT n FROM perto))
    FROM c CROSS JOIN f
   WHERE c.p > 0
     -- 394: a faixa firme da Parceria (225): 20% abaixo, 10% acima
     AND (f.teto IS NULL OR c.p BETWEEN f.teto * 0.80 AND f.teto * 1.10)
     AND (NOT EXISTS (SELECT 1 FROM pedidos) OR c.bn IN (SELECT n FROM pedidos) OR c.bn IN (SELECT n FROM perto))
   ORDER BY (c.bn IN (SELECT n FROM perto)), abs(c.p - coalesce(f.teto, c.p)), c.codigo
   LIMIT least(greatest(coalesce(p_limite, 5), 1), 10)
$function$;

-- a marca nos antigos: parceiro do site antigo (criado antes de outubro), sem a marca à mão do Tel
UPDATE imoveis
   SET extras = coalesce(extras, '{}'::jsonb) || '{"parceiro_antigo": "sim"}'::jsonb
 WHERE e_parceiro
   AND criado_em < '2026-10-01'
   AND coalesce(extras->>'parceiro_manual', '') <> 'sim'
   AND coalesce(extras->>'parceiro_antigo', '') <> 'sim';

COMMIT;
