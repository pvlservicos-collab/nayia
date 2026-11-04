-- teste da 595 (roda dentro da transação do ensaio, antes do ROLLBACK)
\pset format aligned
\echo '== quantos em cada lista e linha'
SELECT lista, linha, count(*) AS contatos, sum(cardinality(codigos)) AS imoveis, count(*) FILTER (WHERE falou_conosco_60d) AS falou_60d
  FROM privado.campanha_contato WHERE estado = 'preparada' GROUP BY ROLLUP (lista, linha) ORDER BY 1, 2;
\echo '== garantias (todos 0)'
SELECT (SELECT count(*) FROM (SELECT 1 FROM privado.campanha_contato WHERE estado <> 'cancelada' GROUP BY chave, dia HAVING count(*) > 1) x) AS repetido_no_dia,
       (SELECT count(*) FROM privado.campanha_contato WHERE tel8 = ANY (site_painel_internos())) AS numero_da_casa,
       (SELECT count(*) FROM privado.campanha_contato WHERE lista <> 'parceiros_disponivel' AND nay_e_corretor_chave(chave)) AS corretor_em_lista_de_dono,
       (SELECT count(*) FROM privado.campanha_contato WHERE linha = 'oficial' AND (modelo IS NULL OR cardinality(modelo_valores) <> 2)) AS oficial_sem_modelo,
       (SELECT count(*) FROM privado.campanha_contato WHERE lista <> 'parceiros_disponivel' AND mensagem_seguinte IS NULL) AS dono_sem_seguinte,
       (SELECT count(*) FROM privado.campanha_contato WHERE mensagem ~ '(null|NULL|  )') AS texto_quebrado;
SELECT id, lista, mensagem FROM privado.campanha_contato WHERE mensagem ~ '(null|NULL|  )' LIMIT 3;
\echo '== exemplo de cada lista e linha'
\x on
SELECT DISTINCT ON (lista, linha) lista, linha, id, nome, '…' || right(telefone, 4) AS tel, codigos, modelo, modelo_valores,
       mensagem, mensagem_seguinte
  FROM privado.campanha_contato WHERE estado = 'preparada' ORDER BY lista, linha, prioridade DESC, id;
\x off
\echo '== textos'
SELECT campanha_vocativo('Construtora Europa - Rodrigo Vanzin Coordenador Belagio') AS construtora,
       campanha_vocativo('Sr. Rossi') AS sr, campanha_vocativo('DOS') AS sigla, campanha_vocativo('Ana Claudia Rego') AS ana,
       campanha_dinheiro(499999) AS dinheiro, campanha_lista_texto(ARRAY['1', '2', '3']) AS lista3;
\echo '== quem mais atende (amostra de cada lista e linha)'
SELECT lista, linha, coalesce(campanha_quem_atende(id), '(ninguém: a campanha responde)') AS quem, count(*)
  FROM (SELECT id, lista, linha FROM privado.campanha_contato WHERE estado = 'preparada' ORDER BY id) x
 GROUP BY 1, 2, 3 ORDER BY 1, 2, 4 DESC;
\echo '== liberar exige quem; libera 2 dos parados; reservar devolve 1 (ou adia quem conversou)'
DO $$ BEGIN PERFORM crm_campanha_liberar('donos_parados', NULL, 1, ''); RAISE EXCEPTION 'deveria recusar sem quem';
EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'deveria%' THEN RAISE; END IF; END $$;
SELECT crm_campanha_liberar('donos_parados', NULL, 2, 'teste') AS liberou_2;
SELECT id, lista, estado, linha FROM campanha_reservar(false);
SELECT id, lista, estado, adiada_motivo, erro FROM privado.campanha_contato WHERE liberada_por = 'teste';
SELECT crm_campanha_cancelar(ARRAY(SELECT id FROM privado.campanha_contato WHERE liberada_por = 'teste' AND estado = 'liberada'), 'teste', 'teste') AS cancelou;
\echo '== o CRM lista (como nay_disparo)'
SET ROLE nay_disparo;
SELECT jsonb_array_length(crm_campanha_listar('donos_parados')->'itens') AS itens_parados, crm_campanha_listar(NULL, 'preparada', 1)->'resumo' AS resumo;
RESET ROLE;
\echo '== baixa: maior recusa, 50% abaixo recusa, menor aceita (o imóvel NÃO muda); destinatários'
WITH c AS (SELECT o.codigo, i.valor_aluguel AS v FROM privado.olx_cliente_enviada o JOIN imoveis i ON i.codigo = o.codigo
            WHERE o.tipo = 'card' AND o.enviado_em > now() - interval '30 days' AND i.status = 'Disponível'
              AND coalesce(i.valor_aluguel, 0) > 0 AND coalesce(i.valor_venda, 0) = 0
            GROUP BY 1, 2 ORDER BY count(*) DESC LIMIT 1)
SELECT c.codigo, c.v, crm_campanha_baixa_confirmar(c.codigo, c.v + 100, 'teste') AS maior,
       crm_campanha_baixa_confirmar(c.codigo, c.v * 0.3, 'teste') AS muito_baixo,
       crm_campanha_baixa_confirmar(c.codigo, c.v - 100, 'teste') AS aceita,
       crm_campanha_baixa_confirmar(c.codigo, c.v - 200, 'teste') AS segunda_aberta FROM c;
SELECT b.id, b.codigo, b.valor_antes, b.valor_novo, (SELECT valor_aluguel FROM imoveis WHERE codigo = b.codigo) AS cadastro_nao_mudou,
       (SELECT count(*) FROM campanha_baixa_destinatarios(b.id)) AS destinatarios
  FROM privado.campanha_baixa b;
\echo '== chaves'
SELECT chave, valor FROM privado.olx_config WHERE chave LIKE 'campanha_%' ORDER BY 1;
