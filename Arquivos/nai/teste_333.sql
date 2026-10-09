-- Testes da 333 (rodam dentro do ensaio, antes do ROLLBACK).
CREATE TEMP TABLE _t (caso text, esperado text, veio text);

INSERT INTO _t SELECT 'não sobra visita com a equipe de dia passado', '0',
  (SELECT count(*)::text FROM nai_visita v WHERE v.estado = 'com_rayssa' AND v.excluida_em IS NULL
      AND (v.quando AT TIME ZONE 'America/Manaus')::date < (now() AT TIME ZONE 'America/Manaus')::date);

INSERT INTO _t SELECT 'as que fecharam agora são todas de dia passado', '0',
  (SELECT count(*)::text FROM nai_visita v WHERE v.motivo = 'Fechada sozinha: o dia da visita passou' AND v.encerrada_em = now()
      AND (v.quando AT TIME ZONE 'America/Manaus')::date >= (now() AT TIME ZONE 'America/Manaus')::date);

INSERT INTO _t SELECT 'fecharam como encerrada, sem ninguém esperando', '0',
  (SELECT count(*)::text FROM nai_visita v WHERE v.motivo = 'Fechada sozinha: o dia da visita passou' AND v.encerrada_em = now()
      AND (v.estado <> 'encerrada' OR v.aguardando IS NOT NULL));

INSERT INTO _t SELECT 'as de hoje e as futuras continuam com a equipe', 'sim',
  CASE WHEN (SELECT count(*) FROM nai_visita v WHERE v.estado = 'com_rayssa' AND v.excluida_em IS NULL
                AND (v.quando AT TIME ZONE 'America/Manaus')::date >= (now() AT TIME ZONE 'America/Manaus')::date) > 0 THEN 'sim' ELSE 'não' END;

INSERT INTO _t SELECT 'nenhuma mensagem foi criada para ninguém', '0',
  (SELECT count(*)::text FROM nai_saida s WHERE s.criado_em = now());

INSERT INTO _t SELECT 'cada uma ganhou o registro do que aconteceu',
  (SELECT count(*)::text FROM nai_visita v WHERE v.motivo = 'Fechada sozinha: o dia da visita passou' AND v.encerrada_em = now()),
  (SELECT count(DISTINCT e.visita_id)::text FROM nai_visita_evento e WHERE e.tipo = 'fechada_pelo_dia' AND e.quando = now());

SELECT nai_visitas_fechar_dia_passado() AS de_novo \gset
INSERT INTO _t SELECT 'rodar de novo não fecha mais nada', '0', :'de_novo';

-- uma visita futura que passa a ser de ontem fecha; as outras ficam
SELECT v.id AS alvo FROM nai_visita v WHERE v.estado = 'com_rayssa' AND v.excluida_em IS NULL
   AND (v.quando AT TIME ZONE 'America/Manaus')::date > (now() AT TIME ZONE 'America/Manaus')::date ORDER BY v.quando LIMIT 1 \gset
SELECT count(*) AS abertas_antes FROM nai_visita v WHERE v.estado = 'com_rayssa' AND v.excluida_em IS NULL \gset
UPDATE nai_visita SET quando = now() - interval '1 day' WHERE id = :alvo;
SELECT nai_visitas_fechar_dia_passado() AS fechou \gset
INSERT INTO _t SELECT 'a que passou a ser de ontem fechou (só ela)', '1/encerrada/' || (:abertas_antes - 1),
  :'fechou' || '/' || (SELECT estado FROM nai_visita WHERE id = :alvo) || '/' ||
  (SELECT count(*) FROM nai_visita v WHERE v.estado = 'com_rayssa' AND v.excluida_em IS NULL);

INSERT INTO _t SELECT 'a agenda chama a regra uma vez', '1',
  ((length(pg_get_functiondef('public.nai_agenda_tick()'::regprocedure))
    - length(replace(pg_get_functiondef('public.nai_agenda_tick()'::regprocedure), 'nai_visitas_fechar_dia_passado()', '')))
   / length('nai_visitas_fechar_dia_passado()'))::text;

INSERT INTO _t SELECT 'para o CRM, as abertas agora são só de hoje em diante', '0',
  (SELECT count(*)::text FROM crm_visitas(NULL, NULL) c WHERE c.aberta
      AND (c.quando AT TIME ZONE 'America/Manaus')::date < (now() AT TIME ZONE 'America/Manaus')::date);

SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso, CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe FROM _t;

DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _t WHERE esperado IS DISTINCT FROM veio;
  IF n > 0 THEN RAISE EXCEPTION '333: % teste(s) falharam', n; END IF;
END $$;
