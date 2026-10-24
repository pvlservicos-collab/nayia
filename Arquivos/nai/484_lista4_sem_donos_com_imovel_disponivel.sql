-- 484 -- Lista 4 (donos que só têm imóvel vendido, outro_imovel_04): tira quem tem imóvel Disponível
-- Pedro, 24/10/2026: "tira dessa lista de donos todos os que estão com imóveis disponíveis e me avisa quantos sobrou".
-- Cruzado pelo telefone e pelo nome com imóvel Disponível (imoveis, imovel_privado, proprietarios): 4 donos da fila.
-- Não apaga nada: o telefone entra em captacao_nao_disparar (a fila do disparo já respeita a tabela) com o motivo.
BEGIN;
INSERT INTO captacao_nao_disparar (telefone_chave, motivo)
SELECT l.telefone_chave, '484: dono com imóvel Disponível (' || v.como || ', imóvel ' || v.codigo || '), lista 4, Pedro 24/10/2026'
  FROM captacao_leads l
  JOIN (VALUES (6254, 'telefone no cadastro do imóvel', 5170), (6036, 'telefone em imovel_privado', 3548),
               (6026, 'mesmo nome, só o primeiro nome', 9002), (6343, 'mesmo nome completo', 5354)) v(id, como, codigo) ON v.id = l.id
 WHERE l.status IN ('novo', 'erro') AND l.quem_importou LIKE 'Pedro (lista 4%'
ON CONFLICT (telefone_chave) DO NOTHING;
SELECT (SELECT count(*) FROM captacao_nao_disparar WHERE motivo LIKE '484:%') AS tirados,
       (SELECT count(*) FROM captacao_py_fila_do_disparo() i JOIN captacao_leads l ON l.id = i WHERE l.quem_importou LIKE 'Pedro (lista 4%') AS sobram_na_fila;
COMMIT;
