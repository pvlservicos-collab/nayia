-- teste da 508 (roda dentro da transação do ensaio, antes do ROLLBACK)
INSERT INTO core_turno (chave, papel, texto, estado_antes, estado_depois, intencao, caminho, usou_modelo, versao_regras,
                        ms_total, fechado_em, modo)
VALUES ('5592999990001', 'corretor', 'teste 508', 'X', 'ESCALADO', 'x', 'pre_roteador', false, 'x', 1, now(), 'real');

INSERT INTO core_saida (turno_id, chave_destino, papel_destino, ordem, tipo, texto, motivo, estado)
VALUES ((SELECT max(id) FROM core_turno), '120363410110464366-group', 'grupo', 9, 'texto',
        'Corretor Kellen (559282717655) na Parceria precisa de uma pessoa da equipe: assunto geral. Ele mandou: "oi".',
        'aviso_grupo', 'pendente'),
       ((SELECT max(id) FROM core_turno), '5592999990001', 'turno', 1, 'texto', 'Certo!', 'resposta', 'pendente');

SELECT papel_destino, estado, bloqueio FROM core_saida WHERE turno_id = (SELECT max(id) FROM core_turno) ORDER BY ordem;

SELECT nay_aviso_equipe('nay-captacao', 'midia', 'Captação (8595)', 'Doriane (559299853679) mandou uma imagem.',
                        '559299853679');
SELECT nay_aviso_equipe('agente', 'esquisito', '', 'Relatório de teste') AS sem_titulo_e_tipo_errado;

SELECT id > 0 AS tem_id, fonte, tipo, titulo, left(texto, 60) texto, telefone FROM crm_avisos_da_equipe(0);
SELECT count(*) AS depois_do_ultimo FROM crm_avisos_da_equipe((SELECT max(id) FROM privado.aviso_equipe));

SET ROLE nay_disparo;
SELECT count(*) AS nay_disparo_le FROM crm_avisos_da_equipe(0);
RESET ROLE;
SET ROLE nay_core;
SELECT nay_aviso_equipe('nay-core', 'escalada', 't', 'nay_core grava') > 0 AS nay_core_grava;
RESET ROLE;
