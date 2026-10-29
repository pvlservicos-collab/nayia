-- 512: as dúvidas dos leads acompanhadas até o fim (Pedro, 28/10/2026, o Felipe ...0843 do 9051: a Nay perguntou à dona as
-- fotos da parte de trás, a dona disse "Vou solicitar", e ninguém voltou na conversa: "preciso que seja criado um script
-- de dúvida, relacionando pessoas diferentes, e seja disparado um cron de tempos em tempos para ver se os proprietários
-- ou os corretores responderam as dúvidas dos leads ... dá um jeito aí para a Nay não esquecer ninguém").
--
-- Até aqui: a dúvida da Nay Leads ia ao agente da vps2 (477), que perguntava ao dono (493); a rotina donos() levava ao
-- agente SÓ a primeira resposta do dono e fechava. "Vou solicitar" fechava a espera, e as 9 dúvidas com o agente
-- (desde 23/10) ficaram paradas. A da Nay Parceria (core_pendencia, 462) nem estado tem.
--
-- privado.duvida liga as pessoas de uma dúvida: QUEM perguntou (o lead do 8595 ou o corretor da Parceria), o imóvel, A
-- QUEM perguntamos (o proprietário, ou o corretor dono do anúncio) e por qual linha, e o andamento. Quem lê e decide é o
-- nay-olx (olx/duvidas.py), de cron: 2 vezes de manhã, 2 à tarde e uma no fim do dia, que manda o resumo às
-- Notificações do CRM.
--
-- nay_duvida_mandar_pela_parceria: a resposta do dono ao corretor da Parceria pela fila do núcleo (core_saida, o mesmo
-- caminho do nay_leads_mandar_pela_parceria, 492, sem marcar a conversa como "Nay Leads com o dono"). Texto ou foto.
BEGIN;

CREATE TABLE IF NOT EXISTS privado.duvida (
  id                  bigserial PRIMARY KEY,
  origem              text        NOT NULL CHECK (origem IN ('pergunta_fila', 'core_pendencia')),
  origem_id           bigint      NOT NULL,
  juntas              bigint[]    NOT NULL DEFAULT '{}',   -- a mesma dúvida repetida (mesma pessoa e imóvel): os outros ids
  linha               text        NOT NULL CHECK (linha IN ('captacao', 'parceria')),
  -- quem perguntou
  cliente_tel         text        NOT NULL,
  cliente_nome        text,
  cliente_papel       text        NOT NULL CHECK (cliente_papel IN ('lead', 'corretor')),
  lead_id             bigint,                              -- privado.olx_lead_whatsapp (linha captacao)
  codigo              integer,
  pergunta            text        NOT NULL,
  perguntada_em       timestamptz NOT NULL,
  -- a quem perguntamos
  dono_tel            text,
  dono_nome           text,
  dono_papel          text        CHECK (dono_papel IN ('proprietario', 'corretor')),
  dono_motivo         text,                                -- sem_cadastro, dois_donos, tratar_com_outra_pessoa...
  dono_linha          text        CHECK (dono_linha IN ('captacao', 'parceria')),
  dono_perguntado_em  timestamptz,
  dono_cobrado_em     timestamptz,
  cobrancas           integer     NOT NULL DEFAULT 0,
  -- o andamento
  estado              text        NOT NULL DEFAULT 'aberta'
                      CHECK (estado IN ('aberta', 'esperando_dono', 'respondida', 'com_o_tel', 'encerrada')),
  situacao            text,                                -- a última leitura (dono_respondeu, dono_vai_ver...)
  resumo              text,
  resposta            text,
  respondida_em       timestamptz,
  cliente_avisado_em  timestamptz,
  checada_em          timestamptz,
  checagens           integer     NOT NULL DEFAULT 0,
  historico           jsonb       NOT NULL DEFAULT '[]',
  criada_em           timestamptz NOT NULL DEFAULT now(),
  atualizada_em       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (origem, origem_id)
);
CREATE INDEX IF NOT EXISTS duvida_aberta ON privado.duvida (perguntada_em) WHERE estado IN ('aberta', 'esperando_dono');
CREATE INDEX IF NOT EXISTS duvida_cliente ON privado.duvida (right(regexp_replace(cliente_tel, '\D', '', 'g'), 8));
CREATE INDEX IF NOT EXISTS duvida_juntas ON privado.duvida USING gin (juntas);
COMMENT ON TABLE privado.duvida IS
  '512: a dúvida de um lead/corretor ligada a quem perguntamos (dono ou corretor) e ao andamento; nay-olx olx/duvidas.py, de cron';
GRANT SELECT, INSERT, UPDATE ON privado.duvida TO nay;
GRANT USAGE ON SEQUENCE privado.duvida_id_seq TO nay;

CREATE OR REPLACE FUNCTION public.nay_duvida_mandar_pela_parceria(p_tel text, p_texto text, p_imagem text DEFAULT NULL,
                                                                   p_codigo integer DEFAULT NULL)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_chave text := nai_chave(p_tel);
  v_turno bigint;
  v_saida bigint;
BEGIN
  IF v_chave IS NULL OR NOT EXISTS (SELECT 1 FROM nai_contato WHERE chave = v_chave)
     OR (btrim(coalesce(p_texto, '')) = '' AND (p_imagem IS NULL OR p_codigo IS NULL)) THEN
    RETURN NULL;
  END IF;
  INSERT INTO core_turno (chave, papel, texto, estado_antes, estado_depois, modo, criado_em, fechado_em)
  VALUES (v_chave, 'agente', '[a resposta da dúvida] ' || left(coalesce(nullif(btrim(p_texto), ''), p_imagem), 200),
          'NAY_DUVIDA', 'NAY_DUVIDA', 'nay_duvida', now(), now())
  RETURNING id INTO v_turno;
  IF p_imagem IS NOT NULL AND p_codigo IS NOT NULL THEN
    INSERT INTO core_saida (turno_id, chave_destino, ordem, tipo, imagem_url, codigo, texto, motivo, papel_destino, estado,
                            enviar_apos, criado_em)
    VALUES (v_turno, v_chave, 1, 'imagem', p_imagem, p_codigo, nullif(btrim(coalesce(p_texto, '')), ''), 'nay_duvida',
            'turno', 'pendente', now(), now())
    RETURNING id INTO v_saida;
  ELSE
    INSERT INTO core_saida (turno_id, chave_destino, ordem, tipo, texto, motivo, papel_destino, estado, enviar_apos, criado_em)
    VALUES (v_turno, v_chave, 1, 'texto', btrim(p_texto), 'nay_duvida', 'turno', 'pendente', now(), now())
    RETURNING id INTO v_saida;
  END IF;
  RETURN v_saida;
END;
$function$;
COMMENT ON FUNCTION public.nay_duvida_mandar_pela_parceria(text, text, text, integer) IS
  '512: a resposta da dúvida (texto ou foto do dono) ao corretor da Parceria, pela core_saida';

INSERT INTO privado.olx_config (chave, valor, descricao, atualizado_por)
VALUES ('duvidas_rotina', 'sim', '512: a rotina das dúvidas (olx/duvidas.py, de cron): sim | teste (só lê e grava, não manda) | nao',
        'nayia 512')
ON CONFLICT (chave) DO NOTHING;

COMMIT;
