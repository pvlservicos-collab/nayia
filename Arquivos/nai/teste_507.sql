-- 507: no 9043, Piscina sai das características do imóvel e fica nas do condomínio
SELECT substring(nai_ficha_completa(9043) from 'CARACTERÍSTICAS DO IMÓVEL: [^\n]*') AS do_imovel;
SELECT substring(nai_ficha_completa(9043) from 'CARACTERÍSTICAS DO CONDOMÍNIO: [^\n]*') AS do_condominio;
SELECT 'piscina fora do imóvel' AS teste,
       substring(nai_ficha_completa(9043) from 'CARACTERÍSTICAS DO IMÓVEL: [^\n]*') !~ 'Piscina' AS ok;
-- imóvel sem o campo do condomínio continua igual
SELECT 'sem o campo, igual' AS teste, nai_ficha_completa(3883) ~ 'CARACTERÍSTICAS DO IMÓVEL' AS ok;
