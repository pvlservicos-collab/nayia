\pset pager off
SELECT nome, bairro, ano, cardinality(proximos) proximos FROM condominio_proximo WHERE origem = 'cadastro' ORDER BY ano DESC, nome;
SELECT de_nome, para_nome, para_recente, mesmo_bairro FROM condominio_proximo_lista
 WHERE de_nome = 'Cond Vision Residence' AND para_recente ORDER BY mesmo_bairro DESC, para_nome;
SELECT count(*) FILTER (WHERE mesmo_bairro) mesmo, count(*) regiao_e_mesmo FROM condominio_proximo_lista;
-- pediu o Vision (recente, 2023): os recentes próximos pela ordem de lançamento
SELECT codigo, condominio, bairro, preco FROM olx_cliente_buscar('{"finalidade":"locacao","tipo":"apartamento","bairros":["Ponta Negra"],"condominio":"Cond Vision Residence"}', '{}', 8);
