-- teste da 448: roda dentro da transação do ensaio (antes do ROLLBACK)
\echo '--- os três consertados (esperado 1621/2237, 1265/1480, 3200)'
SELECT id, nome, taxas FROM condominio_ficha WHERE id IN (699, 751, 753) ORDER BY id;
\echo '--- Residencial Tarumã 3 quartos = 300 e Vista dos Cedros 2 quartos = 550 nos imóveis'
SELECT codigo, quartos, taxa_condominio, taxa_condominio_em IS NOT NULL AS carimbada FROM imoveis
 WHERE codigo IN (5735, 331, 3349, 1563, 5743, 3204, 3687) ORDER BY codigo;
\echo '--- imóvel sem taxa num condomínio com taxa: pega a da ficha (5735 apagado e salvo de novo)'
UPDATE imoveis SET taxa_condominio = NULL WHERE codigo = 5735;
SELECT codigo, taxa_condominio, taxa_condominio_em IS NOT NULL AS carimbada FROM imoveis WHERE codigo = 5735;
\echo '--- valor digitado à mão no imóvel fica (até o condomínio ser salvo de novo)'
UPDATE imoveis SET taxa_condominio = 333 WHERE codigo = 331;
SELECT codigo, taxa_condominio FROM imoveis WHERE codigo = 331;
\echo '--- salvar o condomínio com "1.250,00" leva 1250 a todos os de 3 quartos (inclusive o 331)'
SELECT site_condominio_salvar(147, '{"taxas":[{"quartos":"3","condominio":"1.250,00"}]}'::jsonb) IS NOT NULL AS salvou;
SELECT taxas FROM condominio_ficha WHERE condominio_id = 147;
SELECT codigo, quartos, taxa_condominio FROM imoveis WHERE codigo IN (5735, 331, 3349, 3687) ORDER BY codigo;
\echo '--- a página pública leva o que a taxa inclui'
SELECT i.codigo, site_imovel_publico(i.codigo)->'condo'->'taxa_inclui' AS inclui, site_imovel_publico(i.codigo)->'valores'->'condo' AS taxa
  FROM imoveis i JOIN condominio_ficha cf ON cf.condominio_id = i.condo_id
 WHERE i.publicado_no_site AND i.disponivel AND cf.taxa_inclui <> '{}' AND cf.taxas <> '[]' LIMIT 3;
\echo '--- diferentes da ficha: digitada (esperado 0) e deduzida (os que já tinham valor próprio)'
SELECT t ? 'fonte' AS deduzida, count(*) AS diferentes FROM imoveis i JOIN condominio_ficha cf ON cf.condominio_id = i.condo_id,
       jsonb_array_elements(cf.taxas) t
 WHERE t->>'quartos' = i.quartos::text AND (t->>'condominio') IS NOT NULL AND i.status <> 'Excluído'
   AND i.taxa_condominio IS DISTINCT FROM (t->>'condominio')::numeric GROUP BY 1;
