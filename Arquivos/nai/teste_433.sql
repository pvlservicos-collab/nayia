\pset pager off
SELECT count(*) condominios, count(*) FILTER (WHERE recente) recentes, count(condo_id) ligados,
       count(*) FILTER (WHERE ligado_como LIKE 'parecido%') por_semelhanca FROM condominio_proximo;
SELECT nome, (SELECT c.nome FROM condominios c WHERE c.id = p.condo_id) cadastro, ligado_como
  FROM condominio_proximo p WHERE ligado_como LIKE 'parecido%' ORDER BY ligado_como LIMIT 70;
SELECT count(*) pares, count(DISTINCT de_id) com_lista FROM condominio_proximo_lista;
-- quantos imóveis disponíveis nossos caem num condomínio da planilha (pelo nome normalizado)
SELECT count(*) disponiveis, count(*) FILTER (WHERE EXISTS (SELECT 1 FROM condominio_proximo_nomes n
                                         WHERE n.norma = lower(unaccent(i.condominio_nome)))) na_planilha
  FROM imoveis i WHERE i.status = 'Disponível' AND NOT coalesce(i.e_parceiro, false) AND i.condominio_nome IS NOT NULL;
-- o Jardim das Cerejeiras (recente): os próximos, recentes primeiro
SELECT para_nome, para_recente, mesmo_bairro, ordem FROM condominio_proximo_lista WHERE de_nome ILIKE '%Cerejeiras%'
 ORDER BY para_recente DESC, NOT mesmo_bairro, ordem LIMIT 8;
SELECT count(*) FILTER (WHERE mesmo_bairro) mesmo, count(*) FILTER (WHERE NOT mesmo_bairro) regiao FROM condominio_proximo_lista;
SET ROLE nay_core; SELECT count(*) o_core_le FROM condominio_proximo_nomes; RESET ROLE;
