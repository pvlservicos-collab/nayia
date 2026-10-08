-- dentro do ensaio (ROLLBACK no fim). Roda depois da 317 e da 318 juntas. Nada disto sai nem fica.
SET LOCAL statement_timeout = '60s';
CREATE TEMP TABLE _t (n serial, caso text, esperado text, veio text) ON COMMIT DROP;

\echo == A FILA DO MODELO: quem falta, e o que cada trava tirou
WITH bruto AS (
  SELECT l.id, l.telefone_chave, l.proprietario_id, l.nome FROM captacao_leads l
   WHERE l.status IN ('novo', 'erro') AND l.tentativas < 4 AND NOT l.opt_out AND l.humano_assumiu_em IS NULL)
SELECT (SELECT count(*) FROM bruto) AS novo_ou_erro_sem_gente,
       (SELECT count(*) FROM bruto b WHERE captacao_fora_da_campanha(b.id) IS NOT NULL) AS tira_corretor_ou_parceiro,
       (SELECT count(*) FROM bruto b WHERE EXISTS (SELECT 1 FROM captacao_mensagens m WHERE nay_fone_chave(m.telefone) = b.telefone_chave
                                                    AND m.direcao = 'enviada' AND m.status <> 'Falhou')) AS tira_quem_ja_recebeu_mensagem,
       (SELECT count(*) FROM bruto b WHERE EXISTS (SELECT 1 FROM captacao_leads o WHERE o.id <> b.id AND o.proprietario_id IS NOT NULL
                                                    AND o.proprietario_id = b.proprietario_id
                                                    AND (o.ultimo_envio_em IS NOT NULL OR o.respondeu_em IS NOT NULL))) AS tira_mesmo_dono_ja_chamado,
       (SELECT count(*) FROM bruto b WHERE coalesce(btrim(b.nome), '') = '') AS tira_sem_nome,
       (SELECT count(*) FROM captacao_py_fila_do_disparo()) AS fila_do_modelo;

-- 1. desligado: não reserva ninguém
INSERT INTO _t (caso, esperado, veio)
SELECT 'desligado: motivo e ninguém reservado', 'desligado/0', captacao_py_disparo_motivo() || '/' || (SELECT count(*) FROM captacao_py_reservar_disparo());

-- 2. ligado (e no horário, para o teste): reserva UM, o primeiro da fila, e ele passa a ser do Python
UPDATE captacao_config SET valor = 'sim' WHERE chave = 'python_disparo';
UPDATE captacao_config SET valor = '00:00' WHERE chave IN ('janela_inicio', 'janela_inicio_fds');
UPDATE captacao_config SET valor = '23:59' WHERE chave IN ('janela_fim', 'janela_fim_fds');
UPDATE captacao_config SET valor = '23:58' WHERE chave = 'pausa_inicio';
UPDATE captacao_config SET valor = '23:59' WHERE chave = 'pausa_fim';
SELECT (SELECT min(x) FROM captacao_py_fila_do_disparo() x) AS primeiro, (SELECT count(*) FROM captacao_py_fila_do_disparo()) AS fila \gset
SELECT lead_id AS reservado, telefone AS tel_reservado FROM captacao_py_reservar_disparo() \gset
INSERT INTO _t (caso, esperado, veio)
SELECT 'ligado: reservou o primeiro da fila, que virou do Python', 'true/reservado/true/true',
       (:reservado = :primeiro) || '/' || l.status || '/' || EXISTS (SELECT 1 FROM captacao_motor m WHERE m.lead_id = l.id) || '/' || captacao_e_do_python(l.telefone)
  FROM captacao_leads l WHERE l.id = :reservado;
INSERT INTO _t (caso, esperado, veio)
SELECT 'com um reservado, não reserva outro', 'há um lead reservado/0', captacao_py_disparo_motivo() || '/' || (SELECT count(*) FROM captacao_py_reservar_disparo());

-- 3. o envio registrado: sai da fila, e o intervalo segura o próximo
INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status, message_id)
VALUES (:reservado, :'tel_reservado', 'enviada', 'disparo', 'modelo de teste 317', 'Enviado', 'wamid.teste');
UPDATE captacao_leads SET status = 'enviado', ultimo_envio_em = now(), canal = 'oficial' WHERE id = :reservado;
INSERT INTO _t (caso, esperado, veio)
SELECT 'depois do envio: intervalo, e a fila tem um a menos', 'ainda no intervalo do último disparo/true',
       captacao_py_disparo_motivo() || '/' || ((SELECT count(*) FROM captacao_py_fila_do_disparo()) = :fila - 1);
-- a resposta dele entra como 'Recebido py' (é a Nay em Python que atende)
INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status) VALUES (:reservado, :'tel_reservado', 'recebida', 'texto', 'teste 317 resposta', 'Recebido');
INSERT INTO _t (caso, esperado, veio)
SELECT 'a resposta de quem recebeu o modelo vai para o Python', 'Recebido py', status FROM captacao_mensagens WHERE texto = 'teste 317 resposta';

-- 4. a lista de não disparar tira da fila
SELECT min(x) AS segundo FROM captacao_py_fila_do_disparo() x \gset
INSERT INTO captacao_nao_disparar (telefone_chave, motivo) SELECT telefone_chave, 'teste 317' FROM captacao_leads WHERE id = :segundo;
INSERT INTO _t (caso, esperado, veio)
SELECT 'quem está em captacao_nao_disparar sai da fila', 'false', (:segundo IN (SELECT captacao_py_fila_do_disparo()))::text;

-- 5. 318: imóvel que JÁ ESTÁ no cadastro -> só o valor, sem ficha; o lead de teste (código fictício) continua com a ficha
SELECT l.telefone AS tel_real, l.id AS lead_real FROM captacao_leads l
 WHERE l.codigo ~ '^\d+$' AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = l.codigo::int)
   AND NOT EXISTS (SELECT 1 FROM captacao_cadastro c WHERE c.lead_id = l.id) ORDER BY l.id DESC LIMIT 1 \gset
SELECT captacao_ficha(:'tel_real', 'este', '{"valor": "2.800"}', false) AS f_real \gset
INSERT INTO _t (caso, esperado, veio)
SELECT 'imóvel já cadastrado: só o valor, segue para os outros imóveis', 'true/true/pronto/2.800',
       (:'f_real' LIKE 'o imovel dele ja esta no nosso cadastro, e o valor do aluguel ficou anotado%') || '/' ||
       (:'f_real' LIKE '%tem algum outro imovel alem desse%') || '/' || c.estado || '/' || (c.dados ->> 'valor')
  FROM captacao_cadastro c WHERE c.lead_id = :lead_real;
SELECT captacao_ficha_aviso(:lead_real) IS NULL AS sem_aviso \gset
INSERT INTO _t (caso, esperado, veio) VALUES ('e não fica ficha aberta pedindo pergunta', 't', :'sem_aviso');
SELECT telefone AS tel_teste FROM captacao_leads WHERE id = 835 \gset
DELETE FROM captacao_cadastro WHERE lead_id = 835;
SELECT captacao_ficha(:'tel_teste', 'este', '{"valor": "2.500"}', false) AS f_teste \gset
INSERT INTO _t (caso, esperado, veio)
SELECT 'lead sem imóvel no cadastro (o de teste): ficha inteira, como antes', 'true', (:'f_teste' LIKE '%Quantos quartos%')::text;

\echo == os casos
SELECT n, caso, esperado, veio, CASE WHEN esperado = veio THEN 'ok' ELSE '<<< FALHOU' END AS r FROM _t ORDER BY n;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM _t WHERE esperado IS DISTINCT FROM veio) THEN
    RAISE EXCEPTION 'teste_317_318: % caso(s) falharam', (SELECT count(*) FROM _t WHERE esperado IS DISTINCT FROM veio);
  END IF;
END $$;
