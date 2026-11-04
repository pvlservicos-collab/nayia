-- 599: o 1778 traz o dono (Dunhellington Souza, ...9068); código que não existe não traz nada
SELECT 'dono do 1778' caso, * FROM crm_dono_do_imovel(1778);
SELECT 'inexistente' caso, count(*) FROM crm_dono_do_imovel(999999);
SET ROLE nay_disparo;
SELECT 'pelo papel do CRM' caso, nome IS NOT NULL AS tem_nome FROM crm_dono_do_imovel(1778);
RESET ROLE;
