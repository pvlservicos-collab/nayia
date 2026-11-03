CREATE OR REPLACE FUNCTION public.crm_esteira_automatica(p_dias integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_hoje  date := (now() AT TIME ZONE 'America/Manaus')::date;
  v_dias  int  := least(greatest(coalesce(p_dias, 7), 1), 30);
  v_lig   boolean := nai_cfg('followup_ligado', 'nao') = 'sim' AND nai_cfg('pausada', 'sim') = 'nao' AND nai_cfg('modo', 'desligado') = 'todos';
  v_ini   text := nai_cfg('followup_inicio', '09:00');
  v_fim   text := nai_cfg('followup_fim', '18:00');
  v_out   jsonb := '[]'::jsonb;
BEGIN
  -- 1. Parceria: o dia seguinte ao imóvel enviado
  v_out := v_out || coalesce((
    SELECT jsonb_agg(jsonb_build_object(
             'dia', d.dia, 'quando', ((d.dia::text || ' ' || v_ini)::timestamp AT TIME ZONE 'America/Manaus'),
             'janela', v_ini || ' às ' || v_fim, 'nay', 'Parceria', 'origem', 'parceria_dia_seguinte',
             'titulo', 'Seu cliente tem interesse? (imóvel de ontem)', 'nome', r.nome, 'telefone', r.chave,
             'estado', CASE WHEN v_lig THEN 'previsto' ELSE 'desligado' END,
             'detalhe', 'recebeu o imóvel ' || array_to_string(r.codigos, ', ') ) ORDER BY d.dia, r.primeiro)
      FROM (SELECT g::date AS dia FROM generate_series(v_hoje, v_hoje + v_dias - 1, interval '1 day') g
             WHERE extract(isodow FROM g) <> 7) d
      CROSS JOIN LATERAL (
        SELECT e.chave, array_agg(DISTINCT e.codigo ORDER BY e.codigo) AS codigos, min(e.primeiro_em) AS primeiro,
               (SELECT coalesce(nullif(btrim(k.nome_completo), ''), nullif(btrim(k.nome_whatsapp), ''), e.chave)
                  FROM nai_contato k WHERE k.chave = e.chave) AS nome
          FROM imovel_enviado_no_dia e
         WHERE e.dia = ANY (CASE WHEN extract(isodow FROM d.dia) = 1 THEN ARRAY[d.dia - 2, d.dia - 1] ELSE ARRAY[d.dia - 1] END)
           AND NOT nay_fora_da_regra_do_dia(e.chave)
           AND NOT EXISTS (SELECT 1 FROM nai_followup f WHERE f.chave = e.chave
                            AND f.dia_recebeu = ANY (CASE WHEN extract(isodow FROM d.dia) = 1 THEN ARRAY[d.dia - 2, d.dia - 1] ELSE ARRAY[d.dia - 1] END))
           AND NOT coalesce(nai_e_proprietario_contato((SELECT k.id FROM nai_contato k WHERE k.chave = e.chave)), false)
         GROUP BY e.chave) r), '[]'::jsonb);

  -- 1b. o que já saiu hoje (e o que foi pulado, com o motivo)
  v_out := v_out || coalesce((
    SELECT jsonb_agg(jsonb_build_object(
             'dia', v_hoje, 'quando', f.criado_em, 'nay', 'Parceria', 'origem', 'parceria_dia_seguinte',
             'titulo', 'Seu cliente tem interesse? (imóvel de ontem)',
             'nome', coalesce((SELECT coalesce(nullif(btrim(k.nome_completo), ''), nullif(btrim(k.nome_whatsapp), '')) FROM nai_contato k WHERE k.id = f.contato_id), f.chave),
             'telefone', f.chave, 'estado', f.estado, 'detalhe', coalesce(f.motivo, 'recebeu o imóvel ' || array_to_string(f.codigos::text[], ', '))) ORDER BY f.criado_em)
      FROM nai_followup f WHERE (f.criado_em AT TIME ZONE 'America/Manaus')::date = v_hoje), '[]'::jsonb);

  -- 2. Leads: a visita do cliente da OLX (lembrete e "como foi?")
  v_out := v_out || coalesce((
    SELECT jsonb_agg(jsonb_build_object(
             'dia', (x.quando AT TIME ZONE 'America/Manaus')::date, 'quando', x.quando, 'nay', 'Leads', 'origem', 'leads_visita',
             'titulo', x.titulo, 'nome', coalesce(nullif(btrim(w.nome), ''), 'Cliente do Leads'), 'telefone', w.telefone,
             'estado', 'previsto', 'detalhe', 'visita do imóvel ' || x.codigo) ORDER BY x.quando)
      FROM (SELECT o.lead, o.codigo, o.lembrete_em AS quando, 'Lembrete da visita ao cliente' AS titulo FROM privado.olx_visita o
             WHERE o.lembrete_em > now() AND o.estado NOT IN ('cancelada', 'expirada', 'realizada')
            UNION ALL
            SELECT o.lead, o.codigo, o.depois_em, 'Como foi a visita?' FROM privado.olx_visita o
             WHERE o.depois_em > now() AND o.estado NOT IN ('cancelada', 'expirada')) x
      JOIN privado.olx_lead_whatsapp w ON w.id = x.lead
     WHERE (x.quando AT TIME ZONE 'America/Manaus')::date < v_hoje + v_dias), '[]'::jsonb);

  -- 3. os pedidos nos grupos que repetem (manhã e tarde do dia seguinte, no máximo 2 vezes; a Nay para quando alguém oferece)
  v_out := v_out || coalesce((
    SELECT jsonb_agg(jsonb_build_object(
             'dia', r.dia, 'quando', (r.dia::text || CASE r.vez WHEN 1 THEN ' 09:00' ELSE ' 15:00' END)::timestamp AT TIME ZONE 'America/Manaus',
             'janela', CASE r.vez WHEN 1 THEN 'de manhã' ELSE 'de tarde' END, 'nay', 'Leads', 'origem', 'busca_nos_grupos',
             'titulo', 'Pedir de novo no grupo ' || r.grupo || ' (' || r.vez || 'ª repetição)',
             'nome', coalesce(nullif(btrim(w.nome), ''), 'Cliente do Leads'), 'telefone', w.telefone,
             'estado', 'previsto', 'detalhe', 'se ninguém oferecer imóvel até lá') ORDER BY r.dia, r.vez)
      FROM (SELECT b.lead, g->>'nome' AS grupo, ((g->>'em')::timestamptz AT TIME ZONE 'America/Manaus')::date + 1 AS dia, v.vez
              FROM privado.busca_cliente b, jsonb_array_elements(b.grupos) g, (VALUES (1), (2)) v(vez)
             WHERE b.estado = 'buscando' AND coalesce((g->>'teste')::boolean, false) = false AND coalesce((g->>'repeticao')::boolean, false) = false
               AND coalesce((g->>'encerrou')::boolean, false) = false
               AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(b.grupos) h WHERE h->>'grupo' = g->>'grupo' AND coalesce((h->>'repeticao')::boolean, false)
                                AND ((h->>'em')::timestamptz) > (g->>'em')::timestamptz AND v.vez <= 1)
               AND ((g->>'em')::timestamptz AT TIME ZONE 'America/Manaus')::date + 1 BETWEEN v_hoje AND v_hoje + v_dias - 1) r
      JOIN privado.olx_lead_whatsapp w ON w.id = r.lead), '[]'::jsonb);

  -- 4. sem data: o que está na fila e a Nay chama quando der
  v_out := v_out || jsonb_build_array(
    jsonb_build_object('dia', NULL, 'nay', 'Captação', 'origem', 'retomada_oficial', 'estado', 'fila',
      'titulo', 'Retomada pelo número oficial (quem recebeu a abertura e nunca respondeu)',
      'nome', (SELECT count(*) FROM captacao_retomada_oficial)::text || ' donos na fila', 'detalhe', 'o disparo chama cada um uma vez, sem data marcada'),
    jsonb_build_object('dia', NULL, 'nay', 'Todas', 'origem', 'duvida_cobranca', 'estado', 'fila',
      'titulo', 'Dúvidas esperando o dono (a Nay cobra de hora em hora no horário)',
      'nome', (SELECT count(*) FROM privado.duvida WHERE estado IN ('aberta', 'esperando_dono', 'com_o_tel'))::text || ' dúvidas abertas',
      'detalhe', 'cada uma é cobrada até o dono responder'));
  RETURN v_out;
END
$function$;
