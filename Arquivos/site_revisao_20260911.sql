-- =====================================================================
-- Revisão do site (11/09/2026). Pedidos do Tel:
--   * "não aparecem todos os imóveis"      -> vw_imoveis_todos
--   * "vazou corretor parceiro em Proprietários" -> vw_proprietarios_site
--   * condomínio que sugere e "marca"       -> completar/limpar/ligar
--   * "novo imóvel não funciona"            -> sequência + permissão
-- Nada é apagado. As escritas em dado existente são: nomes de condomínio
-- com código HTML ("&amp;amp;") corrigidos, e imóveis sem condo_id ligados
-- ao condomínio de MESMO nome (só quando o nome casa com UM condomínio).
-- =====================================================================

-- ------------------------------------------------ quem NÃO é proprietário
-- Corretor, parceiro, imobiliária, empresa, conta interna. A mesma regra
-- que a Captação já usava (RE_NAO_E_DONO), agora no banco, para todas as
-- telas lerem igual.
CREATE OR REPLACE FUNCTION site_nao_e_dono(p_nome text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(p_nome, '') ~* '(corretor|corretora|parceir|broker|assessoria|imobili[aá]ri|im[oó]veis|ltda|eireli|construtor|empreendiment|imob ?easy|adm imob|secretari|tratar com)';
$$;

-- ------------------------------------------------ proprietários (site)
-- Base: proprietarios_export -- o cadastro geral do admin antigo (4.220, o
-- mesmo "Todos 4216" do funil de lá). SAI quem tem o selo de parceria
-- (corretor "Imob corretor parceiro" / "Parceiro imob easy") e quem tem
-- nome de corretor/parceiro/empresa/conta interna.
CREATE OR REPLACE VIEW vw_proprietarios_site AS
SELECT pe.id, pe.nome, pe.cpf, pe.email, pe.telefone,
       coalesce(NULLIF(btrim(pe.status), ''), 'Sem etapa') AS etapa,
       NULLIF(btrim(pe.corretor), '') AS especialista,
       pe.criado_em,
       (SELECT count(DISTINCT x.codigo) FROM (
          SELECT ip.codigo::text AS codigo FROM imovel_privado ip WHERE ip.proprietario_id = pe.id
          UNION SELECT pai.codigo FROM proprietarios_admin_imoveis pai WHERE pai.proprietario_id = pe.id) x) AS imoveis,
       (SELECT string_agg(x.codigo, ', ' ORDER BY x.codigo) FROM (
          SELECT ip.codigo::text AS codigo FROM imovel_privado ip WHERE ip.proprietario_id = pe.id
          UNION SELECT pai.codigo FROM proprietarios_admin_imoveis pai WHERE pai.proprietario_id = pe.id) x) AS codigos,
       (SELECT min(c.vencimento) FROM contratos_locacao c
         WHERE c.proprietario_id_admin = pe.id AND c.vencimento IS NOT NULL) AS vencimento
  FROM proprietarios_export pe
 WHERE coalesce(pe.corretor, '') !~* 'parceir'
   AND NOT site_nao_e_dono(pe.nome);

-- ------------------------------------------------ TODOS os imóveis
-- O catálogo (imoveis, 1.225 -- o que o site imobeasy.com mostra) MAIS o
-- que só o admin antigo conhece: alugados, vendidos, arquivados,
-- removidos, rascunho, revisão (~4.400). Um código, uma linha, com status.
CREATE OR REPLACE VIEW vw_imoveis_todos AS
WITH cods AS (
  SELECT codigo FROM imoveis
  UNION SELECT codigo::int FROM imoveis_admin_snapshot WHERE codigo ~ '^[0-9]+$'
  UNION SELECT codigo::int FROM imoveis_admin_detalhe WHERE codigo ~ '^[0-9]+$'
  UNION SELECT codigo FROM imoveis_vendidos
  UNION SELECT codigo FROM imoveis_arquivados
  UNION SELECT codigo FROM imoveis_removidos
  UNION SELECT codigo FROM imoveis_rascunho
  UNION SELECT codigo FROM imoveis_revisao
)
SELECT c.codigo,
       CASE
         WHEN i.codigo IS NOT NULL AND i.disponivel AND i.publicado_no_site THEN 'Disponível'
         WHEN s.status_admin IS NOT NULL THEN s.status_admin
         WHEN v.codigo IS NOT NULL THEN 'Vendido'
         WHEN a.codigo IS NOT NULL THEN 'Arquivado'
         WHEN r.codigo IS NOT NULL THEN 'Removido'
         WHEN ra.codigo IS NOT NULL THEN 'Rascunho'
         WHEN rv.codigo IS NOT NULL THEN 'Em revisão'
         WHEN i.codigo IS NOT NULL AND NOT coalesce(i.disponivel, true) THEN 'Indisponível'
         ELSE 'Fora do site'
       END AS status,
       (i.codigo IS NOT NULL) AS no_catalogo,
       coalesce(i.tipo, d.tipo) AS tipo,
       CASE WHEN coalesce(i.tipo, d.tipo) ~* '^(apartamento|cobertura|flat|kitnet|studio)' THEN 'apartamento'
            WHEN coalesce(i.tipo, d.tipo) ~* '^casa' THEN 'casa'
            WHEN coalesce(i.tipo, d.tipo) IS NULL THEN 'sem_tipo'
            ELSE 'outros' END AS grupo_tipo,
       coalesce(NULLIF(btrim(i.condominio_nome), ''), NULLIF(btrim(d.condominio), ''),
                NULLIF(btrim(coalesce(v.condominio, a.condominio, r.condominio, ra.condominio, rv.condominio)), '')) AS condominio,
       coalesce(i.condo_id, d.condominio_id) AS condo_id,
       coalesce(NULLIF(i.bairro, ''), NULLIF(d.bairro, '')) AS bairro,
       coalesce(NULLIF(concat_ws(', ', NULLIF(i.logradouro, ''), NULLIF(i.numero, '')), ''),
                NULLIF(concat_ws(', ', NULLIF(d.logradouro, ''), NULLIF(d.numero, '')), ''),
                coalesce(v.endereco, a.endereco, r.endereco, ra.endereco, rv.endereco)) AS endereco,
       coalesce(i.valor_venda, d.valor_venda) AS valor_venda,
       coalesce(i.valor_aluguel, d.valor_aluguel) AS valor_aluguel,
       coalesce(v.valor, a.valor, r.valor, ra.valor, rv.valor) AS valor_texto,
       coalesce(i.quartos, d.quartos) AS quartos,
       coalesce(i.vagas, d.vagas) AS vagas,
       coalesce(i.area_util, d.area) AS area,
       coalesce(i.e_parceiro, false) AS e_parceiro,
       CASE WHEN coalesce(i.extras->>'aceita financiamento', d.financiamento, '') ~* '^s' THEN 'Sim'
            WHEN coalesce(i.extras->>'aceita financiamento', d.financiamento, '') ~* '^n' THEN 'Não'
            ELSE '—' END AS financia,
       coalesce(i.publicado_no_site, false) AS publicado_no_site,
       ct.vencimento,
       coalesce(pa.nome, v.proprietario_nome, a.proprietario_nome, r.proprietario_nome,
                ra.proprietario_nome, rv.proprietario_nome) AS proprietario_nome,
       coalesce(i.criado_em, d.captado_em::timestamptz, s.coletado_em,
                v.extraido_em, a.extraido_em, r.extraido_em, ra.extraido_em, rv.extraido_em) AS criado
  FROM cods c
  LEFT JOIN imoveis i ON i.codigo = c.codigo
  LEFT JOIN imoveis_admin_snapshot s ON s.codigo = c.codigo::text
  LEFT JOIN imoveis_admin_detalhe d ON d.codigo = c.codigo::text
  LEFT JOIN imoveis_vendidos v ON v.codigo = c.codigo
  LEFT JOIN imoveis_arquivados a ON a.codigo = c.codigo
  LEFT JOIN imoveis_removidos r ON r.codigo = c.codigo
  LEFT JOIN imoveis_rascunho ra ON ra.codigo = c.codigo
  LEFT JOIN imoveis_revisao rv ON rv.codigo = c.codigo
  LEFT JOIN contratos_locacao ct ON ct.codigo = c.codigo::text
  LEFT JOIN proprietarios_admin pa ON pa.id = s.proprietario_id;

GRANT SELECT ON vw_imoveis_todos TO nay_site_leitura;
GRANT SELECT ON vw_proprietarios_site TO nay_site_leitura;

-- ------------------------------------------------ condomínios
-- 1. Os que o admin antigo conhece e a tabela não tinha (mesmo espaço de id:
--    dos 210 ids nas duas tabelas, 209 têm o mesmo nome).
INSERT INTO condominios (id, nome, bairro)
SELECT DISTINCT ON (d.condominio_id) d.condominio_id, btrim(d.condominio), NULLIF(btrim(d.bairro), '')
  FROM imoveis_admin_detalhe d
 WHERE d.condominio_id IS NOT NULL AND NULLIF(btrim(d.condominio), '') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM condominios c WHERE c.id = d.condominio_id)
 ORDER BY d.condominio_id, d.coletado_em DESC
ON CONFLICT (id) DO NOTHING;

-- 2. Nome com código HTML ("View Club &amp;amp;amp; Home").
UPDATE condominios
   SET nome = replace(replace(replace(replace(replace(replace(nome,
              '&amp;', '&'), '&amp;', '&'), '&amp;', '&'), '&#39;', ''''), '&quot;', '"'), '&#x27;', '''')
 WHERE nome ~ '&(amp|#39|quot|#x27);';

-- 3. Imóvel com nome de condomínio e sem condo_id: liga ao condomínio de
--    MESMO nome (sem acento e sem caixa), só quando o nome casa com UM só.
WITH alvo AS (
  SELECT i.codigo, min(c.id) AS id
    FROM imoveis i
    JOIN condominios c ON lower(nay_sem_acento(btrim(c.nome))) = lower(nay_sem_acento(btrim(i.condominio_nome)))
   WHERE i.condo_id IS NULL AND NULLIF(btrim(i.condominio_nome), '') IS NOT NULL
   GROUP BY i.codigo
  HAVING count(DISTINCT c.id) = 1
)
UPDATE imoveis i SET condo_id = alvo.id FROM alvo WHERE i.codigo = alvo.codigo;

GRANT SELECT ON condominios TO nay_site_escrita;
GRANT UPDATE (condo_id, condominio_nome) ON imoveis TO nay_site_escrita;

-- ------------------------------------------------ novo imóvel pelo site
-- Faixa de código própria (900000+) para NUNCA colidir com o código que o
-- imobeasy.com dá (hoje até 5730) -- a varredura horária sobrescreveria.
-- Nasce com publicado_no_site = false (não aparece no site nem é oferecido
-- pela Nay até alguém publicar).
CREATE SEQUENCE IF NOT EXISTS imoveis_crm_codigo_seq START 900000;
GRANT USAGE ON SEQUENCE imoveis_crm_codigo_seq TO nay_site_escrita;
GRANT INSERT (codigo, tipo, condo_id, condominio_nome, bairro, cidade, estado, logradouro, numero,
              complemento, cep, area_util, area_total, quartos, suites, banheiros, vagas, vagas_cobertas,
              sol, andar, valor_venda, valor_aluguel, taxa_condominio, iptu, mobilia, descricao,
              caracteristicas, origem, publicado_no_site, disponivel, criado_em)
   ON imoveis TO nay_site_escrita;
GRANT SELECT ON condominios TO nay_site_leitura;
GRANT SELECT (nome) ON corretores TO nay_site_leitura;
GRANT SELECT ON clientes_admin_real TO nay_site_leitura;
