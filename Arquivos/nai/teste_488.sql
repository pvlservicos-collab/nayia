-- dentro do ensaio (ROLLBACK): um número qualquer vira corretor classificado por "parceria"
SELECT busca_corretor_e('5592911112222') AS antes;
INSERT INTO privado.busca_corretor (telefone8, telefone, origem, classificado_em) VALUES ('11112222', '5592911112222', 'parceria', now());
SELECT busca_corretor_e('5592911112222') AS classificado;
UPDATE privado.busca_corretor SET estado = 'humano' WHERE telefone8 = '11112222';
SELECT busca_corretor_e('5592911112222') AS com_a_equipe;
SELECT count(*) AS organicos_agora FROM olx_organicos_novos(60);
