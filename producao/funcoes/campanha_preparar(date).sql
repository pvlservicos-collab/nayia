CREATE OR REPLACE FUNCTION public.campanha_preparar(p_dia date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_dia      date := coalesce(p_dia, (now() AT TIME ZONE 'America/Manaus')::date);
  v_internos text[] := site_painel_internos()
                       || coalesce((SELECT array_agg(right(regexp_replace(x, '\D', '', 'g'), 8))
                                      FROM regexp_split_to_table(coalesce((SELECT valor FROM olx_config WHERE chave = 'whatsapp_nunca'), ''), '[,;\s]+') x
                                     WHERE length(regexp_replace(x, '\D', '', 'g')) >= 8), '{}');
  v_res      jsonb;
  v_cancel   int;
BEGIN
  -- a lista é refeita: as preparadas de outro dia que ninguém liberou saem
  UPDATE campanha_contato SET estado = 'cancelada', erro = 'lista refeita em ' || to_char(v_dia, 'DD/MM'), atualizado_em = now()
   WHERE estado = 'preparada' AND dia < v_dia;
  GET DIAGNOSTICS v_cancel = ROW_COUNT;

  DROP TABLE IF EXISTS pg_temp._camp_imovel;
  CREATE TEMP TABLE _camp_imovel ON COMMIT DROP AS
  WITH lst AS (SELECT * FROM cnm_envio_lista(30)),
  gp AS (
    SELECT pp.codigo, count(DISTINCT q.remetente) FILTER (WHERE pp.nota >= 90) AS ped90
      FROM grupo_pedido_par pp JOIN grupo_pedido q ON q.id = pp.pedido_id
     WHERE q.fonte = 'grupo' AND q.enviada_em > now() - interval '30 days'
     GROUP BY pp.codigo
  ), base AS (
    SELECT i.codigo, i.e_parceiro, i.administrado, i.criado_em, i.publicado_no_site,
           (coalesce(l.candidato, false) AND coalesce(l.visitas, 0) = 0 AND coalesce(l.buscados, 0) = 0
            AND coalesce(l.enviados, 0) <= 1 AND coalesce(gp.ped90, 0) <= 1
            AND i.criado_em::date <= v_dia - 30) AS parado,
           EXISTS (SELECT 1 FROM nai_visita v WHERE v.codigo = i.codigo AND nai_visita_aberta(v.estado)
                      AND coalesce(v.quando, v.quando_sugerido, now()) > now() - interval '1 day')
           OR EXISTS (SELECT 1 FROM olx_visita o WHERE o.codigo = i.codigo
                         AND o.estado NOT IN ('cancelada', 'expirada', 'realizada') AND coalesce(o.quando, now()) > now() - interval '1 day')
             AS visita_marcada
      FROM imoveis i LEFT JOIN lst l ON l.codigo = i.codigo LEFT JOIN gp ON gp.codigo = i.codigo
     WHERE i.status = 'Disponível' AND i.disponivel AND NOT i.bloqueado
  )
  SELECT b.*, d.nome AS dono_nome, nay_fone_com_ddi(regexp_replace(coalesce(d.telefone, ''), '\D', '', 'g')) AS dono_tel,
         d.motivo AS dono_motivo, nai_chave(d.telefone) AS chave, NULL::text AS fora
    FROM base b LEFT JOIN LATERAL nai_proprietario_do_imovel(b.codigo) d ON true;

  UPDATE _camp_imovel c SET fora = CASE
      WHEN c.dono_motivo IS NOT NULL THEN c.dono_motivo
      WHEN c.chave IS NULL OR length(c.dono_tel) < 12 THEN 'sem_telefone'
      WHEN right(c.chave, 8) = ANY (v_internos) THEN 'numero_da_casa'
      WHEN EXISTS (SELECT 1 FROM captacao_leads l WHERE l.telefone_chave = c.chave AND l.opt_out) THEN 'pediu_para_nao_receber'
      WHEN c.visita_marcada THEN 'visita_marcada'
      WHEN NOT c.e_parceiro AND c.administrado THEN 'administrado'
      WHEN EXISTS (SELECT 1 FROM campanha_contato x WHERE x.chave = c.chave
                      AND (x.enviada_em > now() - interval '30 days' OR x.estado IN ('liberada', 'enviando'))) THEN 'campanha_nos_ultimos_30_dias'
      END;
  -- corretor nunca entra em lista de proprietário (352): uma conta por telefone
  UPDATE _camp_imovel c SET fora = 'corretor_como_dono'
   WHERE c.fora IS NULL AND NOT c.e_parceiro
     AND c.chave IN (SELECT DISTINCT x.chave FROM _camp_imovel x WHERE x.fora IS NULL AND NOT x.e_parceiro
                        AND nay_e_corretor_chave(x.chave));

  -- (b) donos dos parados, (c) feedback dos outros nossos, (a) corretores dos parceiros. Nessa ordem: o mesmo telefone
  -- num dia fica só na primeira (o índice campanha_contato_um_por_dia).
  INSERT INTO campanha_contato (lista, dia, nome, vocativo, telefone, chave, tel8, linha, modelo, modelo_valores, codigos,
                                imoveis, prioridade, falou_conosco_60d, mensagem, mensagem_seguinte)
  SELECT x.lista, v_dia, x.nome, x.voc, x.tel, x.chave, right(x.chave, 8), x.linha, mo.modelo, mo.valores, x.codigos,
         (SELECT jsonb_agg(jsonb_build_object('codigo', c, 'nome', campanha_imovel_nome(c, false),
                                              'valor_venda', i.valor_venda, 'valor_aluguel', i.valor_aluguel,
                                              'metricas', CASE WHEN x.lista <> 'parceiros_disponivel' THEN campanha_metricas(c) END)
                           ORDER BY o)
            FROM unnest(x.codigos) WITH ORDINALITY u(c, o) JOIN imoveis i ON i.codigo = u.c),
         x.prioridade, nay_falou_conosco(x.chave, 60),
         CASE WHEN x.linha = 'oficial' THEN mo.texto ELSE campanha_msg_primeira(x.lista, x.voc, x.codigos) END,
         campanha_msg_seguinte(x.lista, x.codigos)
    FROM (
      SELECT g.*, campanha_vocativo(g.nome) AS voc, campanha_linha(g.tel) AS linha
        FROM (
          SELECT 1 AS ordem, 'donos_parados' AS lista, c.chave, max(c.dono_tel) AS tel, max(c.dono_nome) AS nome,
                 array_agg(c.codigo ORDER BY c.codigo) AS codigos, 100 + count(*)::int AS prioridade
            FROM _camp_imovel c WHERE c.fora IS NULL AND NOT c.e_parceiro AND c.parado GROUP BY c.chave
          UNION ALL
          SELECT 2, 'feedback_disponiveis', c.chave, max(c.dono_tel), max(c.dono_nome),
                 array_agg(c.codigo ORDER BY c.codigo), 50 + count(*)::int
            FROM _camp_imovel c WHERE c.fora IS NULL AND NOT c.e_parceiro
             AND NOT EXISTS (SELECT 1 FROM _camp_imovel p WHERE p.chave = c.chave AND p.fora IS NULL AND NOT p.e_parceiro AND p.parado)
           GROUP BY c.chave
          UNION ALL
          SELECT 3, 'parceiros_disponivel', c.chave, max(c.dono_tel), max(c.dono_nome),
                 array_agg(c.codigo ORDER BY c.publicado_no_site DESC, c.criado_em DESC, c.codigo DESC),
                 20 * count(*) FILTER (WHERE c.publicado_no_site)::int
                 + CASE WHEN max(c.criado_em) > now() - interval '30 days' THEN 10 ELSE 0 END + least(count(*)::int, 10)
            FROM _camp_imovel c WHERE c.fora IS NULL AND c.e_parceiro GROUP BY c.chave
        ) g
       ORDER BY g.ordem, g.prioridade DESC
    ) x
    LEFT JOIN LATERAL campanha_modelo(x.codigos, x.voc) mo ON x.linha = 'oficial'
   ORDER BY x.ordem, x.prioridade DESC
  ON CONFLICT (chave, dia) WHERE estado <> 'cancelada' DO NOTHING;

  SELECT jsonb_build_object(
           'dia', v_dia,
           'canceladas_de_antes', v_cancel,
           'listas', (SELECT jsonb_object_agg(lista, n) FROM (SELECT lista, count(*) AS n FROM campanha_contato
                                                               WHERE dia = v_dia AND estado = 'preparada' GROUP BY lista) t),
           'linhas', (SELECT jsonb_object_agg(k, n) FROM (SELECT lista || ':' || linha AS k, count(*) AS n FROM campanha_contato
                                                           WHERE dia = v_dia AND estado = 'preparada' GROUP BY 1) t),
           'imoveis_fora', (SELECT jsonb_object_agg(fora, n) FROM (SELECT fora, count(*) AS n FROM _camp_imovel
                                                                     WHERE fora IS NOT NULL GROUP BY fora) t))
    INTO v_res;
  RETURN v_res;
END;
$function$;
