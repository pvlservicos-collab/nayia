-- testes da 370: o roteiro inteiro de cada perfil, pergunta por pergunta (dentro da transação do ensaio)
CREATE FUNCTION pg_temp.roteiro(p_codigo integer, p_negocio text, p_resp jsonb) RETURNS TABLE(n int, campo text, pergunta text)
LANGUAGE plpgsql AS $$
DECLARE v jsonb; i int := 0; v_ins text;
BEGIN
  PERFORM captacao_olx_novo(p_codigo, '5596991712835', 'Pedro');
  UPDATE captacao_olx SET anuncio = anuncio || jsonb_build_object('negocio', p_negocio) WHERE lead_id = (SELECT id FROM captacao_leads WHERE telefone_chave = nay_fone_chave('5596991712835'));
  LOOP
    i := i + 1; EXIT WHEN i > 20;
    v := captacao_olx_proxima('5596991712835');
    IF (v->>'fim')::boolean THEN n := i; campo := 'FIM'; pergunta := captacao_olx_encerrar('5596991712835', 'concluido'); RETURN NEXT; EXIT; END IF;
    n := i; campo := v->>'campo'; pergunta := v->>'pergunta'; RETURN NEXT;
    v_ins := captacao_olx_guardar('5596991712835', v->>'campo', coalesce(p_resp->>(v->>'campo'), 'resposta de teste'));
  END LOOP;
END $$;

\echo '== o lead de teste depois da migração =='
SELECT l.id, l.status, l.etapa, o.codigo, o.anuncio->>'tipo' tipo, o.anuncio->>'condominio' condominio, captacao_olx_perfil(l.id) perfil
  FROM captacao_leads l JOIN captacao_olx o ON o.lead_id = l.id WHERE l.telefone_chave = nay_fone_chave('5596991712835');
\echo '== a primeira pergunta para o Pedro =='
SELECT captacao_olx_proxima('5596991712835');

\echo '== O TESTE DO PEDRO (anuncio sem condominio/elevador/sol/taxa), respondendo "escada" =='
CREATE TEMP TABLE _anuncio_pedro AS SELECT anuncio FROM captacao_olx WHERE lead_id = 835;
DO $$ DECLARE v jsonb; i int := 0; BEGIN
  LOOP i := i + 1; EXIT WHEN i > 20; v := captacao_olx_proxima('5596991712835'); EXIT WHEN (v->>'fim')::boolean;
    RAISE NOTICE '% %: %', i, v->>'campo', v->>'pergunta';
    PERFORM captacao_olx_guardar('5596991712835', v->>'campo', CASE v->>'campo' WHEN 'elevador' THEN 'é de escada' WHEN 'honorarios' THEN 'não, tem que acrescentar' WHEN 'outros' THEN 'tenho uma casa no Tarumã' ELSE 'x' END);
  END LOOP; END $$;
\echo '== VENDA, apartamento com elevador e andar no anuncio (9012 View Club) =='
SELECT * FROM pg_temp.roteiro(9012, 'venda', '{"honorarios":"pode ser 4%"}');
\echo '== LOCACAO, apartamento (9035 Park Golf) =='
SELECT * FROM pg_temp.roteiro(9035, 'locacao', '{"elevador":"tem elevador","outros":"não"}');
\echo '== VENDA, casa de condominio (9025 Quinta das Marinas) =='
SELECT * FROM pg_temp.roteiro(9025, 'venda', '{"honorarios":"sim, incluso","outros":"não"}');
\echo '== LOCACAO, casa de condominio (9024 Reserva das Flores) =='
SELECT * FROM pg_temp.roteiro(9024, 'locacao', '{"outros":"não"}');
\echo '== VENDA, casa de via publica (uma qualquer do cadastro) =='
SELECT * FROM pg_temp.roteiro((SELECT codigo FROM imoveis WHERE tipo = 'Casa' AND coalesce(valor_venda,0) > 0 ORDER BY codigo DESC LIMIT 1), 'venda', '{"outros":"não"}');
\echo '== LOCACAO, casa de via publica =='
SELECT * FROM pg_temp.roteiro((SELECT codigo FROM imoveis WHERE tipo = 'Casa' AND coalesce(valor_aluguel,0) > 0 ORDER BY codigo DESC LIMIT 1), 'locacao', '{"outros":"não"}');
\echo '== encerrar antes da hora (recusa) e opt_out (aceita) =='
SELECT captacao_olx_novo(9012, '5596991712835', 'Pedro') IS NOT NULL AS refeito;
SELECT captacao_olx_encerrar('5596991712835', 'concluido') AS antes_da_hora, captacao_olx_encerrar('5596991712835', 'opt_out') AS opt_out;
