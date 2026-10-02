-- Os turnos que a Nay nova atendeu de verdade, um por linha, com o que ela respondeu. SÓ LEITURA.
-- Uso: ./scripts/nay q scripts/servidor/core_turnos.sql     (os de hoje, do mais antigo ao mais novo)
SELECT to_char(t.criado_em, 'HH24:MI') AS hora, right(t.chave, 4) AS fim, t.caminho, coalesce(t.intencao, '-') AS intencao,
       t.estado_antes || '>' || t.estado_depois AS estado, coalesce(left(t.erro, 60), '') AS erro,
       left(replace(t.texto, E'\n', ' '), 90) AS ele,
       coalesce((SELECT string_agg(s.motivo || CASE WHEN s.papel_destino = 'tel' THEN '>tel' ELSE '' END || ':' || s.estado
                                   || coalesce(' [' || left(s.bloqueio, 50) || ']', ''), ', ' ORDER BY s.ordem)
                   FROM core_saida s WHERE s.turno_id = t.id AND s.tipo = 'texto'), '(silêncio)') AS textos,
       (SELECT count(*) FILTER (WHERE s.estado = 'enviado') || '/' || count(*) FROM core_saida s
         WHERE s.turno_id = t.id AND s.tipo = 'imagem') AS fotos,
       coalesce((SELECT left(replace(s.texto, E'\n', ' / '), 150) FROM core_saida s
                  WHERE s.turno_id = t.id AND s.tipo = 'texto' AND s.papel_destino = 'turno' ORDER BY s.ordem LIMIT 1), '') AS resposta
  FROM core_turno t
 WHERE t.exec_id IS NOT NULL AND t.criado_em::date = current_date
 ORDER BY t.id;
