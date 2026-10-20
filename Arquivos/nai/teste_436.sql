\pset pager off
SELECT origem, count(*), count(*) FILTER (WHERE recente) recentes, count(*) FILTER (WHERE recente_planilha) da_planilha,
       count(ano) com_ano FROM condominio_proximo GROUP BY 1;
SELECT nome, bairro, ano, recente_planilha, origem FROM condominio_proximo WHERE recente
 ORDER BY ano DESC NULLS LAST, nome;
-- quem mexe no cadastro de condomínio (o papel do site) continua gravando: o gatilho roda como dono
SELECT count(*) AS proximos_de_um_recente_novo FROM condominio_proximo_lista WHERE para_nome = 'Paradise River';
