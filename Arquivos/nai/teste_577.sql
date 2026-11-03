-- teste da 577: um envio igual ao da newsletter (o 9118 para o Pedro), e o bloco das fotos; tudo some no ROLLBACK do ensaio
SET LOCAL statement_timeout = '20s';
SELECT nai_disparo_enfileirar('5596991712835', ARRAY[9118], 'newsletter do blog') AS resultado;
UPDATE nai_saida s SET estado = 'bloqueado', bloqueio = 'newsletter do blog: só o card (577)'
  FROM nai_turno t
 WHERE t.id = s.turno_id AND t.papel = 'tel' AND t.criado_em = now()
   AND t.texto LIKE 'disparo pelo painel (newsletter do blog): %'
   AND s.estado = 'pendente' AND s.tipo = 'imagem';
SELECT s.tipo, s.estado, count(*) FROM nai_saida s JOIN nai_turno t ON t.id = s.turno_id
 WHERE t.criado_em = now() AND t.texto LIKE 'disparo pelo painel (newsletter do blog): %' GROUP BY 1, 2 ORDER BY 1;
