CREATE OR REPLACE FUNCTION public.visita_card(p_visita bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH v AS (SELECT * FROM nai_visita WHERE id = p_visita),
  i AS (SELECT x.* FROM imoveis x, v WHERE x.codigo = v.codigo),
  cor AS (SELECT coalesce(nullif(btrim(k.nome_completo), ''), nullif(btrim(k.nome_whatsapp), '')) AS nome, k.chave
            FROM nai_contato k, v WHERE k.id = v.corretor_id),
  dono AS (
    SELECT coalesce(nullif(btrim(v.proprietario_nome), ''), d.nome, nullif(btrim(k.nome_completo), '')) AS nome,
           coalesce(k.chave, nai_chave(d.telefone)) AS chave, d.motivo
      FROM v
      LEFT JOIN nai_contato k ON k.id = v.proprietario_id
      LEFT JOIN LATERAL (SELECT * FROM nai_proprietario_do_imovel(v.codigo) LIMIT 1) d ON true),
  moto AS (
    SELECT coalesce(nullif(btrim(k.nome_completo), ''), k.nome_whatsapp, e.nome) AS nome, coalesce(k.chave, nai_chave(e.telefone)) AS chave
      FROM v
      LEFT JOIN nai_contato k ON k.id = v.motoboy_id
      LEFT JOIN LATERAL (SELECT nome, telefone FROM equipe WHERE papel = 'acompanhante' AND ativo ORDER BY criado_em LIMIT 1) e ON v.motoboy_id IS NULL),
  marco AS (SELECT least(v.criado_em, coalesce(v.quando, v.criado_em)) - interval '24 hours' AS desde FROM v),
  ck AS (
    SELECT
      (SELECT min(s.enviado_em) FROM nai_saida s, v WHERE s.visita_id = v.id AND s.papel_destino = 'proprietario' AND s.estado = 'enviado') AS dono_nay_em,
      (SELECT min(m.criada_em) FROM mensagens m, dono, marco WHERE dono.chave IS NOT NULL AND m.direcao = 'enviada'
          AND right(regexp_replace(m.telefone, '\D', '', 'g'), 8) = right(dono.chave, 8) AND m.criada_em > marco.desde) AS dono_falado_em,
      (SELECT max(m.criada_em) FROM mensagens m, dono, marco WHERE dono.chave IS NOT NULL AND m.direcao = 'recebida'
          AND right(regexp_replace(m.telefone, '\D', '', 'g'), 8) = right(dono.chave, 8) AND m.criada_em > marco.desde) AS dono_respondeu_em,
      -- o motoboy recebe a mensagem de todas as visitas: conta só a que fala DESTA (o código, o condomínio ou o dia)
      (SELECT min(m.criada_em) FROM mensagens m, moto, marco, v LEFT JOIN i ON true WHERE moto.chave IS NOT NULL AND m.direcao = 'enviada'
          AND right(regexp_replace(m.telefone, '\D', '', 'g'), 8) = right(moto.chave, 8) AND m.criada_em > marco.desde
          AND (m.texto LIKE '%' || v.codigo || '%'
               OR (nay_condominio_de_verdade(i.tipo, i.condominio_nome) IS NOT NULL
                   AND lower(unaccent(m.texto)) LIKE '%' || lower(unaccent(nay_condominio_de_verdade(i.tipo, i.condominio_nome))) || '%')
               OR m.texto LIKE '%' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'DD/MM') || '%')) AS moto_falado_em,
      (SELECT max(m.criada_em) FROM mensagens m, moto, marco WHERE moto.chave IS NOT NULL AND m.direcao = 'recebida'
          AND right(regexp_replace(m.telefone, '\D', '', 'g'), 8) = right(moto.chave, 8) AND m.criada_em > marco.desde) AS moto_respondeu_em),
  c AS (
    SELECT v.*, i.tipo, i.bairro, i.logradouro,
           nay_condominio_de_verdade(i.tipo, i.condominio_nome) AS condo,
           cor.nome AS cor_nome, cor.chave AS cor_chave, dono.nome AS dono_nome, dono.chave AS dono_chave, dono.motivo AS dono_motivo,
           moto.nome AS moto_nome, moto.chave AS moto_chave, ck.*,
           to_char(v.quando AT TIME ZONE 'America/Manaus', 'DD/MM') AS dia,
           to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24"h"MI') AS hora,
           (ARRAY['segunda','terça','quarta','quinta','sexta','sábado','domingo'])[extract(isodow FROM v.quando AT TIME ZONE 'America/Manaus')::int] AS dsem
      FROM v LEFT JOIN i ON true LEFT JOIN cor ON true LEFT JOIN dono ON true LEFT JOIN moto ON true LEFT JOIN ck ON true)
  SELECT jsonb_build_object(
    'visita', c.id, 'estado', c.estado, 'quando', to_char(c.quando AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI'),
    'dia', c.dia, 'hora', c.hora, 'dia_semana', c.dsem, 'duracao_min', c.duracao_min,
    'imovel', jsonb_build_object('codigo', c.codigo, 'condominio', c.condo, 'bairro', c.bairro, 'tipo', c.tipo,
                                 'nome', coalesce(c.condo, nai_ref_imovel(c.codigo))),
    'origem', CASE WHEN c.criada_no_crm_por IS NOT NULL THEN 'agenda do CRM (' || c.criada_no_crm_por || ')' ELSE 'pedido pela Nay' END,
    'corretor', jsonb_build_object('nome', c.cor_nome, 'telefone', c.cor_chave, 'confirmou_em', c.confirmada_corretor_em),
    'visitante', c.visitante_nome,
    'proprietario', jsonb_build_object('nome', c.dono_nome, 'telefone', c.dono_chave,
                                        'sem_contato', CASE WHEN c.dono_chave IS NULL THEN coalesce(c.dono_motivo, 'sem telefone no cadastro') END,
                                        'falado', c.dono_falado_em IS NOT NULL OR c.dono_nay_em IS NOT NULL,
                                        'falado_em', to_char(coalesce(c.dono_nay_em, c.dono_falado_em) AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI'),
                                        'pela_nay', c.dono_nay_em IS NOT NULL,
                                        'respondeu', c.dono_respondeu_em IS NOT NULL,
                                        'respondeu_em', to_char(c.dono_respondeu_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI')),
    'motoboy', jsonb_build_object('nome', c.moto_nome, 'telefone', c.moto_chave,
                                   'falado', c.moto_falado_em IS NOT NULL,
                                   'falado_em', to_char(c.moto_falado_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI'),
                                   'respondeu', c.moto_falado_em IS NOT NULL AND c.moto_respondeu_em > c.moto_falado_em),
    'texto',
      '🏠 Visita #' || c.id || ' · ' || coalesce(c.dsem || ', ' || c.dia || ' às ' || c.hora, 'sem dia') || E'\n'
      || '🏢 ' || coalesce(c.condo, nai_ref_imovel(c.codigo), 'imóvel ' || c.codigo) || coalesce(', ' || nullif(btrim(c.bairro), ''), '')
      || ' (cód. ' || c.codigo || ')' || E'\n'
      || '👤 Corretor: ' || coalesce(c.cor_nome, '?') || coalesce(' · ' || nai_fone_fmt(c.cor_chave), '')
      || coalesce(E'\n🙋 Cliente: ' || nullif(btrim(c.visitante_nome), ''), '') || E'\n'
      || CASE WHEN c.dono_falado_em IS NOT NULL OR c.dono_nay_em IS NOT NULL THEN '✅' ELSE '❌' END
      || ' Proprietário: ' || coalesce(c.dono_nome, 'sem nome') || coalesce(' · ' || nai_fone_fmt(c.dono_chave), ' · sem telefone')
      || CASE WHEN (c.dono_falado_em IS NOT NULL OR c.dono_nay_em IS NOT NULL) AND c.dono_respondeu_em IS NOT NULL THEN ' (respondeu)'
              WHEN c.dono_falado_em IS NOT NULL OR c.dono_nay_em IS NOT NULL THEN ' (sem resposta)'
              WHEN c.dono_respondeu_em IS NOT NULL THEN ' (ele escreveu, mas não achei mensagem nossa sobre esta visita)'
              ELSE ' (ninguém falou com ele)' END || E'\n'
      || CASE WHEN c.moto_falado_em IS NOT NULL THEN '✅' ELSE '❌' END
      || ' Motoboy: ' || coalesce(c.moto_nome, 'nenhum') || coalesce(' · ' || nai_fone_fmt(c.moto_chave), '')
      || CASE WHEN c.moto_falado_em IS NOT NULL AND c.moto_respondeu_em > c.moto_falado_em THEN ' (respondeu)'
              WHEN c.moto_falado_em IS NOT NULL THEN ' (sem resposta)'
              ELSE ' (ninguém falou com ele sobre esta visita)' END || E'\n'
      || '📌 ' || CASE WHEN c.criada_no_crm_por IS NOT NULL THEN 'agenda do CRM (' || c.criada_no_crm_por || ')' ELSE 'pedido pela Nay' END
      || ' · estado ' || c.estado)
  FROM c
$function$;
