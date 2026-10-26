-- escolhe 'rayssa' tem que aceitar e calar a Nay como o com_o_tel calava
SELECT * FROM crm_captacao_etapa_manual('5592999990501', 'rayssa', 'teste 501');
SELECT etapa FROM captacao_etapa_manual WHERE telefone = '5592999990501';
-- etapa inválida continua recusando
SELECT * FROM crm_captacao_etapa_manual('5592999990501', 'garagem', 'teste 501');
-- volta para todos limpa de novo
SELECT * FROM crm_captacao_etapa_manual('5592999990501', 'todos', 'teste 501');
SELECT count(*) AS deve_ser_zero FROM captacao_etapa_manual WHERE telefone = '5592999990501';
