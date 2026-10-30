-- 532 (Pedro, 30/10/2026: "sim vira, mas é claro que precisa ter informações mínimas, como as informações que vão no
-- card; tendo isso pode liberar, o que não tiver a Nay pergunta ao corretor"). A busca do cliente sai do modo teste: o
-- imóvel de corretor completo (o mínimo do card: tipo, finalidade, bairro, quartos, área, valor, condomínio, mobília na
-- locação e 3 fotos, nay-olx falta_no_imovel) vai ao cliente da busca. As buscas abertas foram criadas em teste e
-- guardavam a marca (busca_cliente.teste): sem tirar, continuariam só avisando o número de teste.
-- O #9090 (Stela, Piazza Dell'Acqua) ganha a área e as vagas que estavam no anúncio da OLX 1515393241.
BEGIN;

UPDATE privado.olx_config SET valor = 'sim' WHERE chave = 'busca_fluxo';

UPDATE privado.busca_cliente SET teste = false
 WHERE teste AND estado IN ('perfil', 'nossa_base', 'buscando');

UPDATE imoveis SET area_util = coalesce(area_util, 190), vagas = coalesce(vagas, 3)
 WHERE codigo = 9090;

COMMIT;
