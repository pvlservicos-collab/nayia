-- teste da 516 (roda dentro da transação do ensaio, antes do ROLLBACK)
SELECT count(*) AS notas_do_preenchimento FROM privado.aviso_equipe WHERE fonte = 'nay-grupos' AND tipo = 'nota';

INSERT INTO privado.grupo_pedido_oferta (pedido_id, codigo, telefone, abertura, com_card, quem)
SELECT id, 2659, '559299990515', 'Oi! Vi seu pedido lá no grupo', false, 'teste 515' FROM privado.grupo_pedido ORDER BY id DESC LIMIT 1;

SELECT telefone, titulo, texto FROM privado.aviso_equipe WHERE telefone = '559299990515';
SELECT count(*) AS nota_nas_notificacoes FROM crm_avisos_da_equipe(0) WHERE tipo = 'nota';
SET ROLE nay_disparo;
SELECT count(*) AS crm_le_as_notas FROM crm_notas_da_nay(3) WHERE fonte = 'nay-grupos';
RESET ROLE;
