-- teste da 469 (roda depois dela, no ensaio)
\echo '== exemplos: Acquarelle 3q (1125 tinha 1.250), Estilo Golf 2q (9048 tinha 300)'
SELECT i.codigo, i.status, i.quartos, i.taxa_condominio AS agora, a.taxa AS antes
  FROM imoveis i JOIN privado.taxa_imovel_antes_469 a USING (codigo) WHERE i.codigo IN (1125, 9048, 9018, 9041, 2944);
\echo '== imóveis numa ficha com linha para os quartos e taxa diferente da linha (tem de dar 0)'
WITH cf AS (
  SELECT f.id, f.condominio_id, f.taxas,
         array_remove(ARRAY[lower(btrim(f.nome)), lower(btrim(c.nome))]
                      || coalesce((SELECT array_agg(lower(btrim(x))) FROM unnest(f.nomes_no_imovel) x), '{}'), NULL) AS nomes
    FROM condominio_ficha f LEFT JOIN condominios c ON c.id = f.condominio_id)
SELECT count(*) FROM imoveis i JOIN cf ON (cf.condominio_id = i.condo_id
        OR (i.condo_id IS NULL AND lower(btrim(coalesce(i.condominio_nome, ''))) = ANY (cf.nomes))),
       jsonb_array_elements(cf.taxas) t
 WHERE t->>'quartos' = i.quartos::text AND coalesce(i.status, '') <> 'Excluído'
   AND i.taxa_condominio IS DISTINCT FROM (t->>'condominio')::numeric;
\echo '== linhas com fonte (tem de dar 0)'
SELECT count(*) FROM condominio_ficha f, jsonb_array_elements(f.taxas) t WHERE t ? 'fonte';
\echo '== o gatilho: gravar 1 na taxa do 9048 não pega'
UPDATE imoveis SET taxa_condominio = 1 WHERE codigo = 9048;
SELECT codigo, taxa_condominio FROM imoveis WHERE codigo = 9048;
\echo '== as maiores mudanças em imóveis Disponíveis'
SELECT i.codigo, left(i.condominio_nome, 25) cond, i.quartos, a.taxa antes, i.taxa_condominio agora
  FROM imoveis i JOIN privado.taxa_imovel_antes_469 a USING (codigo)
 WHERE i.status = 'Disponível' AND i.taxa_condominio IS DISTINCT FROM a.taxa
 ORDER BY abs(coalesce(i.taxa_condominio, 0) - coalesce(a.taxa, 0)) DESC LIMIT 40;
\echo '== Disponíveis: mudaram / ganharam taxa'
SELECT count(*) FILTER (WHERE a.taxa IS NOT NULL AND a.taxa > 0) mudaram, count(*) FILTER (WHERE coalesce(a.taxa, 0) = 0) ganharam
  FROM imoveis i JOIN privado.taxa_imovel_antes_469 a USING (codigo)
 WHERE i.status = 'Disponível' AND i.taxa_condominio IS DISTINCT FROM a.taxa;
