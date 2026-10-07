-- dentro do ensaio (ROLLBACK no fim): a corretora de final 1994, com quem a Nay nova falou hoje às 08:20.
-- A marca de humano que o Tel deixou ao responder à mão sai só dentro desta transação, para a porta ser julgada.
CREATE TEMP TABLE _t305 ON COMMIT DROP AS
SELECT k.id AS contato, k.chave, k.telefone, coalesce(nai_contato_irmaos(k.id), ARRAY[k.id]) AS ids
  FROM nai_contato k WHERE right(k.chave, 4) = '1994' AND k.chave ~ '^55929' LIMIT 1;
UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = ANY ((SELECT ids FROM _t305)::bigint[]);

SELECT right(chave, 4) AS corretora_fim,
       (SELECT liberado_em IS NOT NULL FROM nai_contato WHERE id = contato) AS liberada,
       (SELECT count(*) FROM nai_saida s WHERE s.contato_id = contato AND s.papel_destino IN ('turno', 'corretor', 'seguimento')) AS respostas_da_velha,
       (SELECT count(*) FROM core_saida s WHERE s.chave_destino = chave AND s.papel_destino = 'turno' AND s.estado = 'enviado') AS mensagens_da_nova
  FROM _t305;

-- 1. a resposta dela ao "Quer que eu te mande as informações e as fotos?": a porta abre
SELECT x.texto, d.atende AS a_atende_esperado_t, d.motivo
  FROM _t305 p, (VALUES ('Isso, por favor 👏✨️'), ('Sim'), ('Nas proximidades'), ('pode mandar')) x(texto),
       LATERAL nai_deve_atender(p.telefone, x.texto, NULL) d;

-- 2. a porta inteira: o turno vai para a Nay nova
SELECT r ->> 'ok' AS b_ok, r ->> 'motivo' AS b_motivo_esperado_core_atende
  FROM _t305 p, LATERAL nai_abrir_turno(p.telefone, NULL, 'Isso, por favor', NULL, '{}'::bigint[]) r;

-- 3. número que nunca falou com ninguém continua do lado de fora com a mesma frase
SELECT d.atende AS c_numero_novo_atende_esperado_f, d.motivo
  FROM nai_deve_atender('5592900000305', 'Isso, por favor', NULL) d;

-- 4. com o Tel tendo escrito agora, a pausa continua vindo antes
UPDATE nai_contato SET humano_assumiu_em = now(), humano_motivo = 'o Tel escreveu pelo celular' WHERE id = (SELECT contato FROM _t305);
SELECT d.atende AS d_com_o_tel_atende_esperado_f, d.motivo
  FROM _t305 p, LATERAL nai_deve_atender(p.telefone, 'Isso, por favor', NULL) d;
