-- 608 (Pedro, 04/11: "poe esses contatos la na captacao, mesmo que nao de pra iniciar conversa"):
-- quem escreveu pelo numero oficial querendo vender e nao virou captacao.
--  * 6 ja tinham lead: so marca quer_vender (e, se estiver vazio, anota o que disseram em imovel_desc);
--  * 5 nao tinham: entram como lead CONCLUIDO (nunca 'novo'), para o disparo nao chamar ninguem.
-- Fora de proposito: 559281275642 e corretor (Kennedy Farias, Creci), nao proprietario.
BEGIN;

UPDATE captacao_leads l
   SET quer_vender = true,
       imovel_desc = coalesce(nullif(l.imovel_desc, ''), v.nota),
       atualizado_em = now()
  FROM (VALUES
    ('5521981691076', 'Indicacao (04/11): o pai dele quer vender a casa'),
    ('559281197777',  'Indicacao (04/11): um amigo quer vender um flat no Mercury'),
    ('559281455686',  'Disse que o imovel esta disponivel para venda'),
    ('559284151942',  'Continua com o apartamento no Authentic para vender'),
    ('559293001033',  'Indicacao (04/11): um primo tem casa nova a venda no Alphaville'),
    ('559296051615',  'Respondeu "Para venda"')
  ) v(tel, nota)
 WHERE l.telefone_chave = nay_fone_chave(v.tel);

INSERT INTO captacao_leads (telefone, nome, status, etapa, quer_vender, imovel_desc, canal)
SELECT v.tel, v.nome, 'concluido', 'concluido', true, v.nota, 'oficial'
  FROM (VALUES
    ('5511972260211', 'Silvia',          'Apartamento na Nossa Senhora de Fatima, quer vender sem exclusividade'),
    ('559281150213',  'Paulo',           'Quer vender no ano que vem, quando acabar o contrato de aluguel'),
    ('559291093142',  'Amanda Alves',    'Desistiu de alugar e deixou para venda'),
    ('559292015390',  'Mattos Servicos', 'Duas casas e um terreno para vender no Tapajos'),
    ('559295333754',  NULL,              'Imovel alugado, querem vender o quanto antes')
  ) v(tel, nome, nota)
 WHERE NOT EXISTS (SELECT 1 FROM captacao_leads x WHERE x.telefone_chave = nay_fone_chave(v.tel));

COMMIT;
