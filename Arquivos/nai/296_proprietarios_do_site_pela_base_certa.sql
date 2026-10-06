-- 296 (05/10/2026, Pedro): "a aba proprietários do site novo tá bugada, não tá aparecendo ninguém, também
-- quando clico em ver alguns imóveis não tem lá ... e tem alguns imóveis com vários proprietários".
--
-- A aba (/api/proprietarios-lista) lê a visão vw_proprietarios_site, que estava montada sobre uma exportação
-- antiga (proprietarios_export, 4.220 pessoas) e contava os imóveis de cada dono por dois vínculos velhos:
-- imovel_privado.proprietario_id (preenchido em 1.174 de 5.691 imóveis) e proprietarios_admin_imoveis (925).
-- Resultado: faltavam 1.457 pessoas do cadastro, a maioria aparecia com "Imóveis: 0", e o mesmo imóvel podia
-- aparecer em dois donos (um vínculo de cada tabela).
--
-- A base certa já está no banco: `proprietarios` (5.677; conferida com a planilha do site antigo em 05/10 --
-- os 5.647 imóveis e os 5.510 donos batem) e o dono de cada imóvel em imoveis.proprietario_id, com
-- imovel_privado.proprietario_id na frente quando alguém trocou o dono pelo site novo. Um imóvel, um dono.
--
-- Só a visão muda. Nenhum dado é alterado. As colunas e os tipos são os mesmos (a API não muda).
BEGIN;

CREATE OR REPLACE VIEW vw_proprietarios_site AS
WITH dono_do_imovel AS (
  SELECT i.codigo, coalesce(ip.proprietario_id, i.proprietario_id) AS proprietario_id
    FROM imoveis i LEFT JOIN imovel_privado ip ON ip.codigo = i.codigo
), do_dono AS (
  SELECT d.proprietario_id, count(*) AS imoveis, string_agg(d.codigo::text, ', ' ORDER BY d.codigo) AS codigos
    FROM dono_do_imovel d WHERE d.proprietario_id IS NOT NULL GROUP BY d.proprietario_id
)
SELECT p.id,
       coalesce(nullif(btrim(p.nome), ''), nullif(btrim(pe.nome), '')) AS nome,
       coalesce(nullif(btrim(p.documento), ''), pe.cpf) AS cpf,
       coalesce(nullif(btrim(p.email), ''), pe.email) AS email,
       coalesce(nullif(btrim(p.telefone), ''), pe.telefone) AS telefone,
       coalesce(nullif(btrim(pe.status), ''), 'Sem etapa') AS etapa,
       nullif(btrim(pe.corretor), '') AS especialista,
       pe.criado_em,
       coalesce(dd.imoveis, 0)::bigint AS imoveis,
       dd.codigos,
       (SELECT min(c.vencimento) FROM contratos_locacao c
         WHERE c.proprietario_id_admin = p.id AND c.vencimento IS NOT NULL) AS vencimento
  FROM proprietarios p
  LEFT JOIN proprietarios_export pe ON pe.id = p.id
  LEFT JOIN do_dono dd ON dd.proprietario_id = p.id
 WHERE coalesce(pe.corretor, '') !~* 'parceir'
   AND NOT site_nao_e_dono(coalesce(nullif(btrim(p.nome), ''), pe.nome));

COMMIT;
