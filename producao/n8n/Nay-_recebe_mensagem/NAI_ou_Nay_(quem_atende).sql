-- NAI atendimento locacao: quem atende esta mensagem? Decide nai_config.modo
-- (desligado / teste / todos). Erro aqui = segue na Nay de sempre.
-- 13/09: com o TEXTO -- no numero do Tel, comando do publicador segue no
-- caminho antigo mesmo com o numero no teste (nai_e_comando_publicador).
SELECT nai_quem_atende($1, $2::boolean, $3) AS atende;
