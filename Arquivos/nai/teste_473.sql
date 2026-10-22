-- teste da 473: o que mudou e o que NÃO pode mudar (situação, disponível, publicado, parceiro)
CREATE TEMP TABLE _antes AS SELECT codigo, status, disponivel, publicado_no_site, e_parceiro, andar FROM imoveis WHERE codigo < 9000;
\echo '--- (a migração já rodou antes deste teste no ensaio; o _antes aqui é DEPOIS) conferência de andar e privado'
SELECT count(*) FILTER (WHERE nullif(btrim(andar),'') IS NOT NULL) AS com_andar FROM imoveis WHERE codigo < 9000 AND status IN ('Disponível','Alugado') AND coalesce(tipo,'') ~* 'apart|cobertura|flat|sala|kitnet|studio|loft';
SELECT i.codigo, i.andar, p.torre, p.bloco, p.unidade FROM imoveis i LEFT JOIN imovel_privado p ON p.codigo = i.codigo WHERE i.codigo IN (99, 150, 193, 5727) ORDER BY 1;
SELECT count(*) FILTER (WHERE nullif(btrim(andar),'') IS NOT NULL) AS com_andar_depois, md5(string_agg(codigo||status||disponivel::text||publicado_no_site::text||coalesce(e_parceiro::text,''), ',' ORDER BY codigo)) AS assinatura FROM imoveis WHERE codigo < 9000;
