-- Resolve o identificador @lid do WhatsApp para o telefone de verdade.
--
-- O PROBLEMA (achado em 29/08, com a Nay já no ar): o WhatsApp está
-- migrando para LID (Linked ID) e a Z-API entrega, em parte das
-- mensagens, `phone` no formato `219958210478302@lid` em vez do número.
-- A MESMA pessoa chega ora de um jeito, ora do outro -- o Leonan tem
-- mensagens nos dois formatos no mesmo dia.
--
-- Por que isso é grave desde o porteiro de 29/08: `corretores.telefone`
-- guarda número. Um corretor chegando por @lid não casa, vira
-- "desconhecido" e recebe a cortesia dizendo que não é parceiro -- ou
-- silêncio. E o próprio Tel aparece como `171210382008357@lid`: nesse
-- formato os comandos dele também morriam.
--
-- POR QUE PELO NOME: a Z-API não manda o telefone junto do @lid em
-- mensagem direta (`participantPhone` vem vazio; conferido no banco de
-- execuções do n8n). O que sobrevive nos dois formatos é o `senderName`.
-- Medido em 29/08: 26 identidades @lid, 26 resolvidas por nome, e NENHUM
-- nome apontando para dois telefones diferentes.
--
-- A REGRA DE SEGURANÇA: nome que aponte para mais de um telefone NÃO
-- resolve. Melhor tratar como desconhecido do que atender uma pessoa
-- achando que é outra -- aqui isso significaria mostrar a conversa e os
-- dados de um corretor a outro.
--
--   docker cp identidade_lid.sql nay-postgres:/tmp/il.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/il.sql

CREATE TABLE IF NOT EXISTS identidade_lid (
  lid       text PRIMARY KEY,
  telefone  text NOT NULL,
  nome      text,
  origem    text NOT NULL DEFAULT 'nome',
  criado_em timestamptz NOT NULL DEFAULT now()
);

-- Semeia com o que o histórico já prova, ignorando nome ambíguo.
INSERT INTO identidade_lid (lid, telefone, nome, origem)
SELECT l.lid, f.telefone, l.nome, 'historico'
  FROM (SELECT DISTINCT telefone AS lid, nome FROM mensagens
         WHERE telefone LIKE '%@lid' AND coalesce(nome,'') <> '') l
  JOIN (SELECT nome, min(telefone) AS telefone
          FROM (SELECT DISTINCT nome, telefone FROM mensagens
                 WHERE telefone NOT LIKE '%@lid' AND coalesce(nome,'') <> '') x
         GROUP BY nome HAVING count(*) = 1) f
    ON f.nome = l.nome
ON CONFLICT (lid) DO NOTHING;

-- Dado um identificador (telefone OU @lid) e o nome que veio na mensagem,
-- devolve o telefone canônico. Aprende sozinho: quando um @lid novo chega
-- com nome que casa com UM único telefone conhecido, grava o vínculo.
CREATE OR REPLACE FUNCTION nay_resolver_identidade(p_id text, p_nome text)
RETURNS text
LANGUAGE plpgsql AS $fn$
DECLARE
  v_id   text := btrim(coalesce(p_id,''));
  v_nome text := btrim(coalesce(p_nome,''));
  v_tel  text;
  v_n    int;
BEGIN
  -- Já é telefone: nada a fazer.
  IF v_id NOT LIKE '%@lid' THEN
    RETURN v_id;
  END IF;

  SELECT telefone INTO v_tel FROM identidade_lid WHERE lid = v_id;
  IF v_tel IS NOT NULL THEN
    RETURN v_tel;
  END IF;

  IF v_nome = '' THEN
    RETURN v_id;
  END IF;

  -- Só resolve se o nome apontar para EXATAMENTE um telefone. Dois
  -- telefones com o mesmo nome viram "não sei", nunca um chute.
  SELECT count(*), min(telefone) INTO v_n, v_tel
    FROM (SELECT DISTINCT telefone FROM mensagens
           WHERE nome = v_nome AND telefone NOT LIKE '%@lid') y;

  IF v_n = 1 AND v_tel IS NOT NULL THEN
    INSERT INTO identidade_lid (lid, telefone, nome, origem)
         VALUES (v_id, v_tel, v_nome, 'nome')
    ON CONFLICT (lid) DO NOTHING;
    RETURN v_tel;
  END IF;

  RETURN v_id;
END;
$fn$;
