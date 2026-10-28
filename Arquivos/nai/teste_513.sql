-- teste da 513 (dentro da transação do ensaio; tudo volta no ROLLBACK)
\echo '--- a agenda dos Leads: quantas e as mais novas'
SELECT count(*) AS visitas_leads FROM crm_visitas_leads(current_date - 14, current_date + 14);
SELECT id, codigo, imovel, estado, aberta, to_char(quando AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') AS quando,
       corretor_nome, right(corretor_telefone, 4) AS corretor, cliente_nome, right(cliente_telefone, 4) AS cliente
  FROM crm_visitas_leads(current_date - 14, current_date + 14) ORDER BY quando DESC LIMIT 6;

\echo '--- a visita do David (#13, 3841, 27/10 14h, confirmada): realizada, pergunta ao corretor'
SELECT * FROM crm_visita_leads_realizada(13, 'corretor', 'Rayssa (teste)');
SELECT id, estado, feedback_para, realizada_por, depois_em IS NULL AS vai_perguntar FROM privado.olx_visita WHERE id = 13;
\echo '--- de novo: recusa'
SELECT * FROM crm_visita_leads_realizada(13, 'cliente', 'Rayssa (teste)');
\echo '--- a que ainda não aconteceu (#14, 31/10) e a escolha errada'
SELECT * FROM crm_visita_leads_realizada(14, 'cliente', 'teste');
SELECT * FROM crm_visita_leads_realizada(12, 'ninguem', 'teste');
\echo '--- o papel do CRM consegue chamar'
SET LOCAL ROLE nay_disparo;
SELECT count(*) AS pelo_crm FROM crm_visitas_leads(NULL, NULL);
RESET ROLE;
