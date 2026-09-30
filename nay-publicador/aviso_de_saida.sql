-- O AVISO DE ALUGADO/VENDIDO SAI POR QUALQUER CAMINHO (Tel, 28/09)
--
-- O QUE ELE VIU: mandou `alugado 5737` pelo número da Imob Easy, a Nay
-- respondeu "Tirei do ar (alugado): 5737 — Amazonas Flat" -- e **não avisou no
-- grupo IMÓVEIS PARA ANUNCIAR EASY**. Os corretores que pegaram aquele anúncio
-- para divulgar continuam divulgando um imóvel que não existe mais.
--
-- POR QUE FALTOU: existem DOIS caminhos para "o imóvel saiu do mercado".
--
--   publicador (`_liberar_vaga`)   tira das vagas, marca indisponível,
--                                  cancela lembretes e entregas, E AVISA NO EASY
--   NAI (`nai_comando_tel`, 22/09) marca indisponível e sabe DESFAZER
--                                  (`DISPONIVEL 5737`) -- mas não fala com grupo
--
-- E quem decide qual roda é o roteador: `alugado 5737` casa
-- `nai_e_comando_imovel`, então vira `comando_nai` e fica na NAI. O aviso, que
-- mora só no outro lado, nunca acontece. Conferido: o 5737 está
-- `disponivel=false` e não há registro de aviso nenhum.
--
-- POR QUE UM GATILHO, e não "mandar a NAI avisar": a NAI é SQL e não fala
-- WhatsApp; fazê-la avisar exigiria um nó novo no fluxo, e ficaríamos com
-- DUAS implementações do mesmo aviso -- que é o padrão que este projeto mais
-- paga. O gatilho fica no BANCO, onde os dois caminhos passam, e vê também o
-- UPDATE feito à mão no psql.
--
-- A FILA É IDEMPOTENTE: postagem em grupo não desfaz, então o que já foi
-- avisado carrega `avisado_em` e nunca sai de novo. Um imóvel que volta
-- (`DISPONIVEL`) e sai outra vez ganha aviso novo, que é o certo -- é uma
-- saída nova.

BEGIN;

CREATE TABLE IF NOT EXISTS aviso_de_saida (
    codigo      text PRIMARY KEY,
    motivo      text,
    marcado_em  timestamptz NOT NULL DEFAULT now(),
    avisado_em  timestamptz,
    erro        text
);

-- O GATILHO: `disponivel` indo para false entra na fila.
--
-- Só a BORDA conta (`IS DISTINCT FROM`): a varredura e os preenchedores tocam
-- a linha o dia inteiro, e sem a borda cada toque reenfileiraria o aviso.
CREATE OR REPLACE FUNCTION nay_enfileirar_aviso_de_saida()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF coalesce(OLD.disponivel, true) AND NOT coalesce(NEW.disponivel, true) THEN
    INSERT INTO aviso_de_saida (codigo, motivo, marcado_em, avisado_em, erro)
    VALUES (NEW.codigo::text, NEW.motivo_bloqueio, now(), NULL, NULL)
    ON CONFLICT (codigo) DO UPDATE
       SET motivo = excluded.motivo, marcado_em = now(),
           avisado_em = NULL, erro = NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS imoveis_aviso_de_saida ON imoveis;
CREATE TRIGGER imoveis_aviso_de_saida
    AFTER UPDATE OF disponivel ON imoveis
    FOR EACH ROW EXECUTE FUNCTION nay_enfileirar_aviso_de_saida();

-- QUEM AINDA DEVE AVISO. A janela existe para o dia em que o cron ficar
-- parado: aviso de uma semana atrás chega sem contexto e confunde mais do que
-- ajuda -- é a mesma razão das 24h do `nay_entregas_devidas`.
CREATE OR REPLACE FUNCTION nay_saidas_a_avisar(p_horas int DEFAULT 6)
RETURNS TABLE(codigo text, motivo text) LANGUAGE sql STABLE AS $$
  SELECT a.codigo, coalesce(a.motivo, 'alugado')
    FROM aviso_de_saida a
    JOIN imoveis i ON i.codigo::text = a.codigo
   WHERE a.avisado_em IS NULL
     AND a.marcado_em > now() - make_interval(hours => p_horas)
     AND NOT coalesce(i.disponivel, true)   -- voltou atrás: não avisa
   ORDER BY a.marcado_em;
$$;

-- A RESERVA ATÔMICA, mesma lição do `postar_easy`: entre "vi que devia" e
-- "avisei" cabe outra rodada do cron, e o grupo receberia duas vezes.
CREATE OR REPLACE FUNCTION nay_reservar_aviso_de_saida(p_codigo text)
RETURNS boolean LANGUAGE sql AS $$
  WITH r AS (
    UPDATE aviso_de_saida SET avisado_em = now()
     WHERE codigo = p_codigo AND avisado_em IS NULL
     RETURNING codigo)
  SELECT count(*) > 0 FROM r;
$$;

CREATE OR REPLACE FUNCTION nay_devolver_aviso_de_saida(p_codigo text, p_erro text)
RETURNS void LANGUAGE sql AS $$
  UPDATE aviso_de_saida SET avisado_em = NULL, erro = p_erro
   WHERE codigo = p_codigo;
$$;

-- O QUE JÁ ESTAVA FORA fica marcado como avisado. Sem isto, a primeira
-- execução despejaria um aviso para cada imóvel indisponível do catálogo --
-- e são mais de cinco mil. É a mesma decisão do detector de visitas: a
-- primeira rodada não processa histórico, só marca o ponto de partida.
INSERT INTO aviso_de_saida (codigo, motivo, marcado_em, avisado_em)
SELECT codigo::text, motivo_bloqueio, now(), now()
  FROM imoveis WHERE NOT coalesce(disponivel, true)
ON CONFLICT (codigo) DO NOTHING;

COMMIT;

SELECT count(*) FILTER (WHERE avisado_em IS NULL) AS a_avisar,
       count(*) AS na_fila
  FROM aviso_de_saida;
