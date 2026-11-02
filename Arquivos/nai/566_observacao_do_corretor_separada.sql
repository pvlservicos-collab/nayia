-- 566 (Pedro, 02/11/2026: "em observações deve estar negócio, se aceita pet, se aceita pôr mais mobília, e não informações
-- internas; se colocar armário fica mais X ... se não tem nada ela não marca nada"). A Nay dos corretores (nay-olx) guardava
-- tudo o que o corretor contava num campo só (extras.observacao_do_corretor), junto com o link da OLX. Daqui para a frente ela
-- separa sozinha (REGRA_DOS_CAMPOS). Aqui os 24 que já estavam assim, separados um a um, à mão:
--   observacao  (sai no card)        só o negócio: disponível a partir de, só à vista, duas cauções
--   descricao   (não sai no card)    os detalhes do imóvel; a Nay lê quando perguntam
--   interno     (Uso interno)        link da OLX, comissão, saldo devedor, o que o corretor contou para nós
--   e os campos que já existem: aceita financiamento, incluso no aluguel.
-- Nenhum dos 24 tinha observação nem descrição; o texto antigo fica no backup /root/backups-funcoes/observacao_do_corretor-2026-11-02.csv.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TEMP TABLE separada (codigo int, observacao text, descricao text, interno text, financiamento text, incluso text) ON COMMIT DROP;
INSERT INTO separada VALUES
 (9061, NULL, 'Semi mobiliado; a cozinha só tem armários novos.', NULL, NULL, NULL),
 (9062, NULL, 'Perto da Faculdade Nilton Lins. Pronta; documentação de compra e venda e IPTU individual.',
        'Corretor informou comissão de R$ 15 mil na venda por R$ 325 mil.', NULL, NULL),
 (9065, NULL, 'Edícula climatizada com jacuzzi, churrasqueira e depósito; painéis de energia solar.', NULL, NULL, NULL),
 (9070, NULL, 'Posição nascente, varanda gourmet, aquecedor a gás. 2 banheiros.', NULL, 'Sim', NULL),
 (9076, 'Disponível a partir de 15/12.', NULL, NULL, NULL, NULL),
 (9081, NULL, 'Nascente.', NULL, 'Sim', NULL),
 (9082, NULL, 'Atrás da Igreja Universal, na Constantino. Construída em todo o terreno, sem quintal.', NULL, 'Sim', NULL),
 (9083, NULL, 'Sala de estar e jantar, armários planejados, climatizada, piscina, edícula, banheiro de serviço e área de serviço.', NULL, NULL, NULL),
 (9084, NULL, '5 banheiros. IPTU anual de R$ 2.300.', 'Saldo devedor de R$ 550.000; parcelas de R$ 5.000.', NULL, NULL),
 (9090, NULL, 'Vista para a avenida.', NULL, NULL, NULL),
 (9093, NULL, 'Reserva do Parque; recém-construída, com espaço gourmet e lavabo.', NULL, NULL, NULL),
 (9097, 'Somente à vista.', 'Rua fechada.', NULL, 'Não', NULL),
 (9098, NULL, NULL, NULL, NULL, NULL),
 (9099, 'Duas cauções (o proprietário não abre mão).', NULL, NULL, NULL, NULL),
 (9103, NULL, NULL, NULL, NULL, NULL),
 (9107, NULL, 'Fica em rua pública.', NULL, NULL, NULL),
 (9108, NULL, NULL, NULL, NULL, NULL),
 (9109, NULL, 'Com energia solar.', NULL, NULL, NULL),
 (9110, NULL, NULL, 'O primeiro link está com contrato de promessa de venda. Também foram informados imóveis em Dom Pedro com 4 e 3 dormitórios, e em Ponta Negra com 3 dormitórios.', NULL, NULL),
 (9111, NULL, NULL, NULL, NULL, NULL),
 (9112, NULL, NULL, NULL, 'Sim', NULL),
 (9113, NULL, 'Um quarto fica fora.', NULL, NULL, 'Taxa de Condomínio, IPTU'),
 (9114, NULL, NULL, NULL, NULL, NULL),
 (9115, NULL, NULL, 'Disponibilidade a confirmar.', NULL, NULL);

-- o link da OLX que estava no texto vai para o interno de cada um
UPDATE separada s SET interno = concat_ws(' ', s.interno, 'Anúncio da OLX: ' || substring(i.extras->>'observacao_do_corretor' FROM 'https?://[^ ]*[0-9]') || '.')
  FROM imoveis i WHERE i.codigo = s.codigo AND (i.extras->>'observacao_do_corretor') ~ 'Anúncio da OLX: https?://';

UPDATE imoveis i SET
  observacao = coalesce(i.observacao, s.observacao),
  descricao  = coalesce(i.descricao, s.descricao),
  extras = (i.extras - 'observacao_do_corretor')
           || CASE WHEN s.financiamento IS NOT NULL AND NOT i.extras ? 'aceita financiamento'
                   THEN jsonb_build_object('aceita financiamento', s.financiamento) ELSE '{}'::jsonb END
           || CASE WHEN s.incluso IS NOT NULL AND NOT i.extras ? 'incluso no aluguel'
                   THEN jsonb_build_object('incluso no aluguel', s.incluso) ELSE '{}'::jsonb END
  FROM separada s
 WHERE i.codigo = s.codigo AND i.extras ? 'observacao_do_corretor';

SELECT privado.uso_interno_somar(codigo, 'Do corretor (Nay dos corretores): ' || interno) FROM separada WHERE interno IS NOT NULL;

SELECT i.codigo, i.observacao, left(i.descricao, 60) descricao, i.extras->>'aceita financiamento' fin,
       left((SELECT observacoes FROM privado.imovel_ficha f WHERE f.codigo = i.codigo), 80) interno
  FROM imoveis i JOIN separada s ON s.codigo = i.codigo ORDER BY 1;
COMMIT;
