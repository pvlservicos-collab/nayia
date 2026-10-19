-- 417 (nasceu 415, que colidiu com 415_grade_grupos_marcados de outra sessão): o follow-up da Nay alcança quem recebeu imóvel no SÁBADO (19/10/2026)
--
-- Pedro, sobre a lacuna que achei: "corrijo para a segunda pegar o sábado também? -- sim". O nai_followup_rodar não
-- roda no domingo e só olhava o dia anterior: na segunda via o domingo, e quem recebeu imóvel no sábado nunca recebia
-- o "seu cliente tem interesse?" (10/10 e 17/10 sem nenhum). Agora, na segunda, olha sábado e domingo; quem recebeu nos
-- dois ganha um só (o dia gravado é o último). A previsão do card do CRM (414) segue a mesma regra.
-- Backups: /root/backups-funcoes/nai_followup_rodar-2026-10-19-415.sql (o rótulo do backup ficou 415) e crm_parceria_followup_nay-...-415.sql
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.nai_followup_rodar()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_hoje   date := (now() AT TIME ZONE 'America/Manaus')::date;
  v_hora   time := (now() AT TIME ZONE 'America/Manaus')::time;
  r        record;
  v_ct     bigint;
  v_ids    bigint[];
  v_chaves text[];
  v_nome   text;
  v_pula   text;
  v_feitos int := 0;
  v_lim    int := greatest(nai_cfg_int('followup_por_minuto', 2), 1);
  v_dias   date[];
BEGIN
  IF nai_cfg('followup_ligado', 'nao') <> 'sim' THEN RETURN 0; END IF;
  IF nai_cfg('pausada', 'sim') <> 'nao' OR nai_cfg('modo', 'desligado') <> 'todos' THEN RETURN 0; END IF;
  IF extract(isodow FROM now() AT TIME ZONE 'America/Manaus') = 7 THEN RETURN 0; END IF;   -- domingo
  IF v_hora < nai_cfg('followup_inicio', '09:00')::time OR v_hora > nai_cfg('followup_fim', '18:00')::time THEN RETURN 0; END IF;

  -- 415: na segunda, o sábado também (domingo ela não roda; antes o sábado nunca ganhava follow-up). O dia gravado é o
  -- último em que recebeu; quem recebeu no sábado E no domingo ganha um só.
  v_dias := CASE WHEN extract(isodow FROM v_hoje) = 1 THEN ARRAY[v_hoje - 2, v_hoje - 1] ELSE ARRAY[v_hoje - 1] END;
  FOR r IN
    SELECT e.chave, array_agg(DISTINCT e.codigo ORDER BY e.codigo) AS codigos, min(e.primeiro_em) AS primeiro,
           max((e.primeiro_em AT TIME ZONE 'America/Manaus')::date) AS dia
      FROM imovel_enviado_no_dia e
     WHERE (e.primeiro_em AT TIME ZONE 'America/Manaus')::date = ANY (v_dias)
       AND NOT EXISTS (SELECT 1 FROM nai_followup f WHERE f.chave = e.chave AND f.dia_recebeu = ANY (v_dias))
     GROUP BY e.chave
     ORDER BY min(e.primeiro_em)
  LOOP
    EXIT WHEN v_feitos >= v_lim;
    v_pula := NULL;
    SELECT id INTO v_ct FROM nai_contato WHERE chave = r.chave;
    IF v_ct IS NULL THEN v_ct := nai_contato_do_cadastro(r.chave, NULL); END IF;
    v_ids := nai_contato_irmaos(v_ct);
    SELECT array_agg(chave) INTO v_chaves FROM nai_contato WHERE id = ANY (v_ids);

    IF nay_fora_da_regra_do_dia(r.chave) THEN
      v_pula := 'equipe ou teste';
    ELSIF EXISTS (SELECT 1 FROM nai_followup f WHERE f.chave = ANY (v_chaves) AND f.dia_recebeu = ANY (v_dias)) THEN
      v_pula := 'a outra linha dele já recebeu';
    ELSIF EXISTS (SELECT 1 FROM mensagens m WHERE nai_chave(m.telefone) = ANY (v_chaves) AND m.direcao = 'recebida'
                   AND m.criada_em > r.primeiro AND nai_recusou(m.texto)) THEN
      v_pula := 'recusou';
    ELSIF EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = ANY (v_ids) AND nai_visita_aberta(x.estado)) THEN
      v_pula := 'visita em andamento';
    ELSIF nai_tel_com_a_conversa(v_ct) THEN
      v_pula := 'o Tel está com a conversa';
    ELSIF EXISTS (SELECT 1 FROM mensagens m WHERE nai_chave(m.telefone) = ANY (v_chaves) AND m.direcao = 'recebida'
                   AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = v_hoje) THEN
      v_pula := 'já conversou hoje';
    ELSIF EXISTS (SELECT 1 FROM nai_corretor_pergunta q WHERE q.chave = ANY (v_chaves) AND q.decisao = 'nao') THEN
      v_pula := 'o Tel disse que não é corretor';
    ELSIF btrim(nai_cfg('so_estes_numeros', '')) <> '' AND NOT nai_na_lista_curta(v_ct, r.chave) THEN
      v_pula := 'fora da lista curta';
    END IF;

    IF v_pula IS NOT NULL THEN
      INSERT INTO nai_followup (chave, dia_recebeu, contato_id, codigos, estado, motivo)
      VALUES (r.chave, r.dia, v_ct, r.codigos, 'pulado', v_pula) ON CONFLICT DO NOTHING;
      CONTINUE;
    END IF;

    SELECT nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)) INTO v_nome FROM nai_contato k WHERE k.id = v_ct;
    INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, texto, ordem, motivo, enviar_apos)
    VALUES (NULL, v_ct, 'seguimento', '', 'texto',
            'Oi' || coalesce(' ' || v_nome, '') || ', seu cliente tem interesse?', 1, 'followup', now());
    INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, texto, ordem, motivo, enviar_apos)
    VALUES (NULL, v_ct, 'seguimento', '', 'texto',
            coalesce(v_nome || ', q', 'Q') || 'ualquer coisa temos muitas opções de imóveis para locação e venda, '
            || 'o que está procurando para seus clientes?', 2, 'followup', now() + interval '8 seconds');
    INSERT INTO nai_followup (chave, dia_recebeu, contato_id, codigos, estado)
    VALUES (r.chave, r.dia, v_ct, r.codigos, 'enviado') ON CONFLICT DO NOTHING;
    v_feitos := v_feitos + 1;
  END LOOP;
  RETURN v_feitos;
END;
$function$;

CREATE OR REPLACE FUNCTION public.crm_parceria_followup_nay(p_telefone text)
RETURNS TABLE(estado text, quando timestamptz, mensagem text, motivo text, codigos integer[])
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
  WITH p AS (
    SELECT pe.contato_id, pe.chaves FROM crm_pessoas(ARRAY[p_telefone]) pe LIMIT 1
  ), cfg AS (
    SELECT (now() AT TIME ZONE 'America/Manaus')::date AS hoje,
           (now() AT TIME ZONE 'America/Manaus')::time AS hora,
           nai_cfg('followup_inicio', '09:00')::time AS ini,
           nai_cfg('followup_fim', '18:00')::time AS fim,
           nai_cfg('followup_ligado', 'nao') = 'sim' AND nai_cfg('pausada', 'sim') = 'nao'
             AND nai_cfg('modo', 'desligado') = 'todos' AS ligado
  ), nome AS (
    SELECT nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)) AS v
      FROM p JOIN nai_contato k ON k.id = p.contato_id
  ), texto AS (
    SELECT 'Oi' || coalesce(' ' || (SELECT v FROM nome), '') || ', seu cliente tem interesse?' || E'\n'
           || coalesce((SELECT v FROM nome) || ', q', 'Q')
           || 'ualquer coisa temos muitas opções de imóveis para locação e venda, o que está procurando para seus clientes?'
           AS t
  ), recebeu AS (     -- o dia em que recebeu imóvel (de anteontem a hoje), em Manaus
    SELECT (e.primeiro_em AT TIME ZONE 'America/Manaus')::date AS dia, array_agg(DISTINCT e.codigo ORDER BY e.codigo) AS codigos
      FROM imovel_enviado_no_dia e, p, cfg
     WHERE e.chave = ANY (p.chaves)
       AND (e.primeiro_em AT TIME ZONE 'America/Manaus')::date BETWEEN cfg.hoje - 2 AND cfg.hoje
     GROUP BY 1
  ), rodada AS (     -- 415: a rodada que pega cada dia: o dia seguinte; o sábado vai para a segunda (domingo não roda)
    SELECT r.*, CASE WHEN extract(isodow FROM r.dia + 1) = 7 THEN r.dia + 2 ELSE r.dia + 1 END AS dia_da_rodada
      FROM recebeu r
  ), previsto AS (
    SELECT 'previsto'::text AS estado,
           greatest(now(), (r.dia_da_rodada + cfg.ini) AT TIME ZONE 'America/Manaus') AS quando,
           (SELECT t FROM texto) AS mensagem,
           'a Nay confere na hora: pula se ele já conversou no dia, recusou, tem visita aberta ou está com o Tel'::text AS motivo,
           r.codigos
      FROM rodada r, cfg, p
     WHERE cfg.ligado
       AND NOT EXISTS (SELECT 1 FROM nai_followup f WHERE f.chave = ANY (p.chaves) AND f.dia_recebeu >= r.dia)
       AND (r.dia_da_rodada > cfg.hoje OR (r.dia_da_rodada = cfg.hoje AND cfg.hora <= cfg.fim))
  ), feitos AS (
    SELECT f.estado, f.criado_em AS quando,
           CASE WHEN f.estado = 'enviado' THEN (SELECT t FROM texto) END AS mensagem,
           f.motivo, f.codigos
      FROM nai_followup f, p
     WHERE f.chave = ANY (p.chaves)
     ORDER BY f.criado_em DESC
     LIMIT 5
  )
  SELECT * FROM previsto
  UNION ALL
  SELECT * FROM feitos
$function$;

COMMIT;
