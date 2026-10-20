\pset pager off
-- sem condomínio: a mesma busca de antes
SELECT codigo, condominio, bairro, preco, perto FROM olx_cliente_buscar('{"finalidade":"locacao","tipo":"apartamento","bairros":["Adrianópolis"]}', '{}', 6);
-- pediu o Barão da Villa (normal): os normais próximos primeiro
SELECT codigo, condominio, bairro, preco, perto FROM olx_cliente_buscar('{"finalidade":"locacao","tipo":"apartamento","bairros":["Adrianópolis"],"condominio":"Barão da Villa"}', '{}', 6);
-- pediu o Jardim das Cerejeiras (recente), sem bairro: o bairro vem da planilha, os recentes próximos primeiro
SELECT codigo, condominio, bairro, preco, perto FROM olx_cliente_buscar('{"finalidade":"locacao","tipo":"apartamento","condominio":"Jardim das Cerejeiras"}', '{}', 6);
-- pediu casa no Passaredo até 10 mil (a Cristina)
SELECT codigo, condominio, bairro, preco, perto FROM olx_cliente_buscar('{"finalidade":"locacao","tipo":"casa","teto":10000,"condominio":"Passaredo"}', '{}', 6);
