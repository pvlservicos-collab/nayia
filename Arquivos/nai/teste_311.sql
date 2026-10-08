-- dentro do ensaio (ROLLBACK no fim). Nada disto sai nem fica.
CREATE TEMP TABLE _t (n serial, caso text, esperado text, veio text) ON COMMIT DROP;

-- 1. o texto do Pedro, letra por letra (venda, à noite)
INSERT INTO _t (caso, esperado, veio)
SELECT 'venda às 20h: igual ao texto colado', 'true',
       (crm_anuncio_mensagem('{"tipo": "apartamento", "bairro": "Flores", "quartos": 3}', 'venda', '2026-10-08 20:00-04') =
$t$Oii, boa noite! Me chamo Nay Mendes, da Imob Easy.

Tenho uns clientes procurando imóveis na região do seu!

Posso apresentar pra eles?

Se gostarem, eu cuido de tudo: visita, documentação, contrato e assinatura. Sem exclusividade, você continua vendendo aqui no OLX.

Me passa seu nome e seu WhatsApp que a gente conversa melhor.$t$)::text;

-- 2. aluguel de manhã: bom dia e "anunciando"
INSERT INTO _t (caso, esperado, veio)
SELECT 'aluguel às 9h: bom dia e "anunciando"', 'true',
       (m LIKE 'Oii, bom dia! Me chamo Nay Mendes, da Imob Easy.%' AND m LIKE '%você continua anunciando aqui no OLX.%')::text
  FROM crm_anuncio_mensagem('{"tipo": "casa", "bairro": "Ponta Negra"}', 'aluguel', '2026-10-08 09:00-04') m;

-- 3. à tarde, sem saber se é venda ou aluguel: boa tarde e "anunciando"
INSERT INTO _t (caso, esperado, veio)
SELECT 'às 15h sem finalidade: boa tarde e "anunciando"', 'true',
       (m LIKE 'Oii, boa tarde!%' AND m LIKE '%você continua anunciando aqui no OLX.%')::text
  FROM crm_anuncio_mensagem('{"titulo": "Sala comercial"}', NULL, '2026-10-08 15:00-04') m;

-- 4. não sobra nada do modelo antigo, em nenhum tipo de imóvel
INSERT INTO _t (caso, esperado, veio)
SELECT 'sem cliente inventado, sem bairro e sem marcador, em todos os tipos', 'true',
       bool_and(m !~* 'família|casal|empresa procurando|na região de |na sua região|[{}]'
                AND m LIKE '%Tenho uns clientes procurando imóveis na região do seu!%')::text
  FROM (VALUES ('{"tipo": "apartamento", "quartos": 3, "bairro": "Nossa Senhora das Graças"}'::jsonb),
               ('{"tipo": "apartamento", "quartos": 1}'), ('{"tipo": "casa", "bairro": "Tarumã"}'),
               ('{"tipo": "sala comercial"}'), ('{"tipo": "terreno"}'), ('{"titulo": "imóvel"}')) x(p),
       crm_anuncio_mensagem(x.p, 'venda', now()) m;

-- 5. a consulta inteira devolve o texto novo (pedido de teste: não grava)
INSERT INTO _t (caso, esperado, veio)
SELECT 'a consulta devolve o texto novo', 'abordar/true',
       (r ->> 'seria') || '/' || (r ->> 'mensagem_exemplo' LIKE '%Tenho uns clientes procurando imóveis na região do seu!%')::text
  FROM crm_anuncio_decidir('{"teste": true, "link": "https://am.olx.com.br/regiao-de-manaus/imoveis/teste-311-9000000311",
    "titulo": "Apartamento no Residencial Zzzinexistente", "tipo": "apartamento", "finalidade": "venda", "preco": 123456789, "bairro": "Flores"}') r;

\echo == os casos
SELECT n, caso, esperado, veio, CASE WHEN esperado = veio THEN 'ok' ELSE '<<< FALHOU' END AS r FROM _t ORDER BY n;
\echo == a mensagem como sai agora (venda)
SELECT crm_anuncio_mensagem('{"tipo": "apartamento"}', 'venda', now()) AS mensagem;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM _t WHERE esperado IS DISTINCT FROM veio) THEN
    RAISE EXCEPTION 'teste_311: % caso(s) falharam', (SELECT count(*) FROM _t WHERE esperado IS DISTINCT FROM veio);
  END IF;
END $$;
