-- 548 (dentro do ensaio: tudo volta no ROLLBACK)
-- 1. o que o dono diz
SELECT '1 frases' AS caso, t AS texto, nai_dono_disse_que_saiu(t) AS saiu
  FROM unnest(ARRAY['Bom dia' || chr(10) || 'Loquei pra um parente por 2100', 'ainda não aluguei', 'Já vendi',
                    'não está mais disponível', 'se alugar te aviso', 'quero alugar o meu apartamento',
                    'o 205 foi alugado ontem']) t;
-- o dono do 205 (contato 21646) diz que alugou: o 205 sai da oferta e a equipe é avisada
INSERT INTO nai_turno (contato_id, papel, texto) VALUES (21646, 'proprietario', 'Bom dia, loquei o apartamento pra um parente por 2100');
SELECT '1 bloqueado' AS caso, codigo, status, bloqueado, left(motivo_bloqueio, 90) FROM imoveis WHERE codigo = 205;
SELECT '1 aviso' AS caso, fonte, tipo, titulo, left(texto, 160) FROM privado.aviso_equipe WHERE criado_em = now() AND fonte = 'porta';
-- "ainda não aluguei" não faz nada
INSERT INTO nai_turno (contato_id, papel, texto) VALUES (21646, 'proprietario', 'ainda não aluguei não');
SELECT '1 negação: 1 aviso só' AS caso, count(*) FROM privado.aviso_equipe WHERE criado_em = now() AND fonte = 'porta';

-- 2. a porta da visita
SELECT '2 pedido novo?' AS caso, t AS texto, nai_pede_imovel_novo(t) AS vai_a_nay
  FROM unnest(ARRAY['Bom dia mana' || chr(10) || 'Tem apto proximo ao Distrito ate 1.800?', 'procuro casa no Aleixo até 3 mil',
                    'Tem como enviar a localização da casa do Aleixo?', 'Eles entregam com ar condicionado?   E o valor chega a 2.700 ?',
                    'Consegue me passar a localização para enviar para o cliente?', 'Ok']) t;
SELECT '2 aviso da porta' AS caso,
       nai_porta_avisar_equipe(21381, 'corretor', 'visita_com_a_rayssa', 'Eles entregam com ar condicionado? E o valor chega a 2.700 ?') AS a1,
       nai_porta_avisar_equipe(21381, 'corretor', 'visita_com_a_rayssa', 'Quak a documentação solicitada ?') AS a2_20min,
       nai_porta_avisar_equipe(5809, 'corretor', 'visita_com_a_rayssa', 'Ok') AS a3_ok,
       nai_porta_avisar_equipe(5809, 'proprietario', 'proprietario_com_a_rayssa', 'qual o horário?') AS a4_dono;
SELECT '2 avisos (1)' AS caso, titulo, left(texto, 200) FROM privado.aviso_equipe WHERE criado_em = now() AND titulo LIKE '%escreveu durante%';
-- a função da porta compila com o bloco novo
SELECT '2 porta' AS caso, prosrc LIKE '%nai_pede_imovel_novo(v_texto)%' AND prosrc LIKE '%nai_porta_avisar_equipe(v_contato%' AS ok
  FROM pg_proc WHERE proname = 'nai_abrir_turno';
