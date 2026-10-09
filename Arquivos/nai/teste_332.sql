INSERT INTO cadastro_rapido_palpite (fonte, item, categoria, porque, base) VALUES ('ficha', 72, 'indisponivel', 'teste', 'x');
SET ROLE nay_site_leitura;
SELECT fonte, item, categoria FROM cadastro_rapido_palpite;
RESET ROLE;
SET ROLE nay_site_escrita;
SELECT count(*) AS escrita_le FROM cadastro_rapido_palpite;
RESET ROLE;
