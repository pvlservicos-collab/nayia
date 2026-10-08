-- 312 (08/10/2026): A NAY NÃO PÕE MAIS VISITA NA AGENDA.
-- Pedro perguntou se a Nay cria o evento da visita na aba Agenda (o calendário do
-- CRM); cria, desde 29/09 (166). A ordem dele: "não faz mais isso, deixa que a
-- Rayssa cria manualmente depois de negociar com o proprietário".
--
-- O QUE CONTINUA IGUAL quando o corretor confirma a visita com a Nay: o pedido
-- vai ao proprietário, a Rayssa e o Tel são avisados, a conversa do corretor vai
-- para a etapa Visitas do CRM e a Nay se cala para ele. Tudo isso depende da
-- linha em nai_visita, que continua nascendo.
--
-- O QUE MUDA: essa linha não aparece mais na Agenda. A agenda (crm_visitas) passa
-- a mostrar só a visita que GENTE pôs lá (criada_no_crm_por) -- e as da Nay que já
-- estavam no calendário antes desta migração, para ninguém perder visita marcada
-- (hoje há três: 09/10, 10/10 e 12/10). A data do corte fica em nai_config
-- (`agenda_sem_visita_da_nay_desde`); apagar a chave volta ao que era.
--
-- E QUANDO A RAYSSA AGENDA À MÃO o que a Nay pediu (mesmo corretor, mesmo
-- imóvel): o pedido da Nay VIRA a visita dela, com o dia e a hora que ela
-- escolheu -- não nasce uma segunda linha. Sem isso haveria duas visitas abertas
-- para a mesma coisa, e a trava do clique duplo responderia "essa visita já está
-- na agenda" apontando para uma visita que a agenda não mostra.
--
-- Patch nas funções vivas (pg_get_functiondef), cada troca conferida uma vez.
BEGIN;
SET LOCAL lock_timeout = '3s';

INSERT INTO nai_config (chave, valor, descricao)
VALUES ('agenda_sem_visita_da_nay_desde', now()::text,
        '312: a partir desta data a visita que vem da Nay NÃO entra na Agenda do CRM; quem põe é a equipe, à mão. Apagar a chave volta a mostrar todas.')
ON CONFLICT (chave) DO NOTHING;

DO $do$
DECLARE
  v_def text;
  PARES text[];
BEGIN
  -- 1. a agenda ---------------------------------------------------------------
  v_def := pg_get_functiondef('public.crm_visitas(date,date)'::regprocedure);
  PARES := ARRAY[
    $a$   WHERE v.estado <> 'coletando'$a$,
    $b$   WHERE v.estado <> 'coletando'
     -- 312: o pedido de visita que vem da Nay não entra mais na agenda; quem põe é a equipe, à mão
     AND (v.criada_no_crm_por IS NOT NULL
          OR v.criado_em < (SELECT nai_cfg('agenda_sem_visita_da_nay_desde', 'infinity')::timestamptz))$b$];
  IF (length(v_def) - length(replace(v_def, PARES[1], ''))) / length(PARES[1]) <> 1 THEN
    RAISE EXCEPTION '312: o trecho da agenda não aparece exatamente uma vez em crm_visitas';
  END IF;
  EXECUTE replace(v_def, PARES[1], PARES[2]);

  -- 2. o agendamento à mão ------------------------------------------------------
  v_def := pg_get_functiondef('public.crm_visita_agendar(integer,text,text,timestamptz,integer,text)'::regprocedure);
  PARES := ARRAY[
    $a$  v_outra bigint;$a$,
    $b$  v_outra bigint;
  v_da_nay bigint;
  v_corte  timestamptz := nai_cfg('agenda_sem_visita_da_nay_desde', 'infinity')::timestamptz;$b$,

    $a$  -- a mesma visita duas vezes (clique duplo, ou duas pessoas agendando igual)$a$,
    $b$  -- 312: o pedido que veio da Nay (fora da agenda) para este corretor e este imóvel
  -- vira ESTA visita, em vez de nascer outra
  SELECT v.id INTO v_da_nay FROM nai_visita v
   WHERE v.codigo = p_codigo AND v.corretor_id = v_cor AND v.estado = 'com_rayssa'
     AND v.criada_no_crm_por IS NULL AND v.excluida_em IS NULL AND v.criado_em >= v_corte
   ORDER BY v.id DESC LIMIT 1
     FOR UPDATE;

  -- a mesma visita duas vezes (clique duplo, ou duas pessoas agendando igual)$b$,

    $a$     AND v.estado NOT IN ('encerrada', 'cancelada', 'expirada') AND v.excluida_em IS NULL
   LIMIT 1;$a$,
    $b$     AND v.estado NOT IN ('encerrada', 'cancelada', 'expirada') AND v.excluida_em IS NULL
     AND (v.criada_no_crm_por IS NOT NULL OR v.criado_em < v_corte)   -- a que a agenda não mostra não trava
   LIMIT 1;$b$,

    $a$  INSERT INTO nai_visita (codigo, corretor_id, proprietario_id, proprietario_cadastro, proprietario_nome,$a$,
    $b$  IF v_da_nay IS NOT NULL THEN
    -- (com o apelido `v`: proprietario_nome também é coluna de SAÍDA desta função)
    UPDATE nai_visita v
       SET quando = p_quando, duracao_min = v_dur, criada_no_crm_por = v_quem,
           proprietario_id = coalesce(v.proprietario_id, v_prop),
           proprietario_cadastro = coalesce(v.proprietario_cadastro, dono.cadastro_id),
           proprietario_nome = coalesce(v.proprietario_nome, dono.nome),
           aprovada_em = now(), aprovada_por = left('CRM: ' || v_quem, 120), atualizado_em = now()
     WHERE v.id = v_da_nay;
    v_id := v_da_nay;
    PERFORM nai_evento(v_id, 'agendada_no_crm', left(v_quem || ' pôs na agenda o pedido que veio pela Nay, ' || v_dur || ' min', 200));
  ELSE
  INSERT INTO nai_visita (codigo, corretor_id, proprietario_id, proprietario_cadastro, proprietario_nome,$b$,

    $a$  PERFORM nai_evento(v_id, 'agendada_no_crm', left(v_quem || ' agendou à mão, ' || v_dur || ' min', 200));$a$,
    $b$  PERFORM nai_evento(v_id, 'agendada_no_crm', left(v_quem || ' agendou à mão, ' || v_dur || ' min', 200));
  END IF;$b$];
  FOR i IN 1 .. array_length(PARES, 1) / 2 LOOP
    IF (length(v_def) - length(replace(v_def, PARES[2 * i - 1], ''))) / length(PARES[2 * i - 1]) <> 1 THEN
      RAISE EXCEPTION '312: o trecho % não aparece exatamente uma vez em crm_visita_agendar', i;
    END IF;
    v_def := replace(v_def, PARES[2 * i - 1], PARES[2 * i]);
  END LOOP;
  EXECUTE v_def;
END
$do$;
COMMIT;
