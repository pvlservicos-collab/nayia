-- teste da 526: quem perde o Prop no WhatsApp Leads, com o porquê, e o tempo
\timing on
SET LOCAL ROLE nay_disparo;
SELECT c.fone8, d.nome, c.motivo FROM crm_captacao_corretores() c LEFT JOIN LATERAL (SELECT nome FROM crm_captacao_donos() x WHERE right(regexp_replace(x.telefone, '\D', '', 'g'), 8) = c.fone8 LIMIT 1) d ON true ORDER BY d.nome;
RESET ROLE;
