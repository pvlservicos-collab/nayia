-- Vigia do núcleo novo (nay-core) atendendo de verdade. SÓ LEITURA. Telefones só com os 4 últimos dígitos.
-- Uso: ./scripts/nay q scripts/servidor/core_vigia.sql
\echo == interruptor
SELECT chave, valor FROM nai_config WHERE chave LIKE 'core_atende%';
\echo == desde que ligou (02/10 14:13 de Manaus): turnos entregues, atendidos e parados
SELECT (SELECT count(*) FROM nai_core_turno WHERE criado_em > '2026-10-02 14:13') AS entregues_pela_porta,
       (SELECT count(*) FROM core_turno WHERE exec_id IS NOT NULL AND criado_em > '2026-10-02 14:13') AS atendidos_pelo_core,
       (SELECT count(*) FROM core_turno WHERE exec_id IS NOT NULL AND erro IS NOT NULL AND criado_em > '2026-10-02 14:13') AS com_erro,
       (SELECT count(*) FROM nai_core_turno e WHERE e.criado_em BETWEEN '2026-10-02 14:13' AND now() - interval '1 minute'
           AND NOT EXISTS (SELECT 1 FROM core_turno t WHERE t.exec_id = e.turno_id::text)) AS entregues_sem_atender;
\echo == a caixa do core, por estado
SELECT s.estado, s.papel_destino, count(*), max(s.tentativas) AS max_tentativas, left(max(s.bloqueio), 80) AS ultimo_bloqueio
  FROM core_saida s JOIN core_turno t ON t.id = s.turno_id WHERE t.exec_id IS NOT NULL AND t.criado_em > '2026-10-02 14:13' GROUP BY 1, 2;
\echo == os ultimos turnos de verdade
SELECT to_char(t.criado_em AT TIME ZONE 'America/Manaus', 'HH24:MI') AS hora, right(t.chave, 4) AS final, t.caminho, coalesce(t.intencao, '-') AS intencao,
       t.estado_depois, left(replace(t.texto, E'\n', ' '), 70) AS ele,
       (SELECT string_agg(s.motivo || CASE WHEN s.papel_destino = 'tel' THEN '>tel' ELSE '' END || ':' || s.estado, ', ' ORDER BY s.ordem)
          FROM core_saida s WHERE s.turno_id = t.id AND s.tipo = 'texto') AS textos,
       (SELECT count(*) FROM core_saida s WHERE s.turno_id = t.id AND s.tipo = 'imagem') AS fotos
  FROM core_turno t WHERE t.exec_id IS NOT NULL AND t.criado_em > '2026-10-02 14:13' ORDER BY t.id DESC LIMIT 15;
\echo == as duas responderam a mesma pessoa no mesmo minuto? (tem que ser zero)
SELECT count(*) AS respostas_em_dobro FROM core_saida c JOIN core_turno t ON t.id = c.turno_id
 WHERE t.exec_id IS NOT NULL AND c.papel_destino = 'turno' AND c.criado_em > '2026-10-02 14:13'
   AND EXISTS (SELECT 1 FROM nai_saida n JOIN nai_contato k ON k.id = n.contato_id
                WHERE k.chave = c.chave_destino AND n.papel_destino = 'turno' AND n.estado IN ('enviado', 'enviando', 'pendente')
                  AND n.criado_em BETWEEN c.criado_em - interval '60 seconds' AND c.criado_em + interval '60 seconds');
\echo == o eco do core carimbou "o Tel escreveu"? (tem que ser zero)
SELECT count(*) AS carimbos_falsos FROM nai_contato k
 WHERE k.humano_motivo = 'o Tel escreveu pelo celular' AND k.humano_assumiu_em > '2026-10-02 14:13'
   AND EXISTS (SELECT 1 FROM core_saida s WHERE s.chave_destino = k.chave AND s.estado = 'enviado'
                AND s.enviado_em BETWEEN k.humano_assumiu_em - interval '2 minutes' AND k.humano_assumiu_em + interval '10 seconds');
\echo == o que ficou com a Nay velha desde que ligou (por motivo)
SELECT coalesce(t.papel, '?') AS papel, count(*) AS turnos,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM nai_core_turno e WHERE e.turno_id = t.id)) AS entregues_ao_core
  FROM nai_turno t WHERE t.criado_em > '2026-10-02 14:13' AND NOT t.teste GROUP BY 1 ORDER BY 2 DESC;
