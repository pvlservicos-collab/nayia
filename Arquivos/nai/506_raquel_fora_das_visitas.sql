-- 506 (27/10/2026, Pedro: "descadastra a raquel de parceria nossa"): a Raquel (Paiva, 92 99466-6884) sai da lista de
-- corretores que a Nay Leads chama para visita. Ficam Neila e Katherine.
BEGIN;
UPDATE privado.olx_config
   SET valor = 'Neila:5592984118226, Katherine:5592981218346'
 WHERE chave = 'visita_corretores' AND valor = 'Raquel:5592994666884, Neila:5592984118226, Katherine:5592981218346';
COMMIT;
