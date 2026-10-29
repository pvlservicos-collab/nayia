-- teste da 523: quem fica embaixo da conversa (só donos) e que Diego, Raquel, Neila e Katherine saíram
SELECT r.cliente, r.contato, r.codigos FROM crm_contatos_relacionados() r ORDER BY r.em DESC;
SELECT count(*) FILTER (WHERE contato IN ('82092845','94666884','84118226','81218346')) AS corretores_e_motoboy, count(*) AS total FROM crm_contatos_relacionados();
