-- =====================================================================
-- 164 — O CADASTRO PELA CONVERSA DA CAPTAÇÃO (28/09/2026)
--
-- Pedro: "veja o fluxo de cadastro se estiver disponível, lembro que tava
-- bugado; precisa pedir as informações certinhas do imóvel para recadastrar
-- qualquer coisa, ou se ele mandar um imóvel novo, cadastrar o imóvel novo dele".
--
-- O BUG ERA DE FERRAMENTA, não de prompt:
--   * guardar_outro_imovel devolvia "gravado. agradeça e ENCERRE" -- a Nay
--     nunca pedia informação nem foto do imóvel novo; ele virava uma frase
--     solta em captacao_imoveis_extra (13 desde 09/09, nenhum curado);
--   * guardar_situacao, com "disponível" + valor, devolvia "agora pergunte se
--     ele tem outro imóvel" -- o pedido de informações e fotos do prompt era
--     atropelado, e nada do imóvel disponível chegava a lugar nenhum.
--
-- AGORA: uma FICHA por imóvel (captacao_cadastro). Quem decide a próxima
-- pergunta é o banco (captacao_ficha), uma de cada vez, na forma do
-- tratamento -- a mesma parede do captacao_encerrar: o modelo não esquece e
-- não repete. O dono que não sabe ("não sei") conta como respondido.
--   atualizar (o imóvel da campanha, disponível): cômodos e área só se o
--     cadastro não tiver; condomínio/IPTU/o que o aluguel inclui; mobília; fotos.
--   novo (outro imóvel dele): tipo e local, alugar ou vender, cômodos, área,
--     valor, condomínio/IPTU, mobília, fotos.
-- Nada vai sozinho para o site: a ficha pronta aparece no painel (Captação
-- WhatsApp) para um humano "Aplicar no imóvel" ou "Criar pré-cadastro" -- a
-- mesma regra da captação pela OLX.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS captacao_cadastro (
  id            bigserial PRIMARY KEY,
  lead_id       bigint NOT NULL,
  tipo          text NOT NULL CHECK (tipo IN ('atualizar', 'novo')),
  codigo        int,                            -- atualizar: o imóvel do catálogo; novo: o pré-cadastro, quando criado
  dados         jsonb NOT NULL DEFAULT '{}'::jsonb,
  fotos         jsonb NOT NULL DEFAULT '[]'::jsonb,   -- URLs já guardadas no nosso servidor
  estado        text NOT NULL DEFAULT 'coletando'
                CHECK (estado IN ('coletando', 'pronto', 'aplicado', 'descartado')),
  criado_em     timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  aplicado_em   timestamptz,
  aplicado_por  text
);
CREATE INDEX IF NOT EXISTS captacao_cadastro_lead_idx ON captacao_cadastro (lead_id, estado);
COMMENT ON TABLE captacao_cadastro IS
  'A ficha que a Nay de captação monta na conversa (164): imóvel disponível a recadastrar ou imóvel novo do dono. Um humano aplica no painel.';

GRANT SELECT, UPDATE ON captacao_cadastro TO nay_site_escrita;
GRANT INSERT ON captacao_cadastro TO nay_site_escrita;
GRANT USAGE ON SEQUENCE captacao_cadastro_id_seq TO nay_site_escrita;

-- "R$ 2.500,00" -> 2500 ; "650 mil" -> 650000 ; "2,5 mil" -> 2500 ; "80 m2" -> 80
CREATE OR REPLACE FUNCTION captacao_numero(p text) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  m text[];
  n numeric;
BEGIN
  m := regexp_match(lower(coalesce(p, '')), '(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d+))?\s*(mil)?');
  IF m IS NULL THEN
    RETURN NULL;
  END IF;
  n := replace(m[1], '.', '')::numeric;
  IF m[2] IS NOT NULL THEN
    n := n + ('0.' || m[2])::numeric;
  END IF;
  IF m[3] = 'mil' THEN
    n := n * 1000;
  END IF;
  RETURN n;
END $$;

-- A FICHA. p_resposta = false quando quem chama é guardar_situacao ou
-- guardar_outro_imovel (é a abertura, não a resposta à última pergunta).
CREATE OR REPLACE FUNCTION captacao_ficha(p_telefone text, p_qual text, p_campos jsonb, p_resposta boolean DEFAULT true)
RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
  l        captacao_leads%ROWTYPE;
  c        captacao_cadastro%ROWTYPE;
  i        imoveis%ROWTYPE;
  v_tipo   text := CASE WHEN lower(coalesce(p_qual, '')) IN ('outro', 'novo') THEN 'novo' ELSE 'atualizar' END;
  v_novos  jsonb;
  v_resp   jsonb;
  v_trat   text;
  v_nome   text;
  v_pron   text;
  v_pron_m text;
  v_voc    text;
  v_aluga  boolean;
  v_cond   boolean;
  v_falta  text[];
  v_prox   text;
  v_frase  text;
  d        jsonb;
BEGIN
  SELECT * INTO l FROM captacao_leads WHERE telefone_chave = nay_fone_chave(p_telefone) ORDER BY id DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN 'nao achei este proprietario na lista. siga o roteiro normalmente e NAO diga que anotou.';
  END IF;

  SELECT * INTO c FROM captacao_cadastro
   WHERE lead_id = l.id AND tipo = v_tipo AND estado = 'coletando' ORDER BY id DESC LIMIT 1;
  IF NOT FOUND THEN
    INSERT INTO captacao_cadastro (lead_id, tipo, codigo)
    VALUES (l.id, v_tipo, CASE WHEN v_tipo = 'atualizar' AND l.codigo ~ '^\d+$' THEN l.codigo::int END)
    RETURNING * INTO c;
  END IF;

  -- o que ele disse agora: só as chaves da ficha, texto limpo
  SELECT coalesce(jsonb_object_agg(k, btrim(v)), '{}'::jsonb) INTO v_novos
    FROM jsonb_each_text(coalesce(p_campos, '{}'::jsonb)) AS e(k, v)
   WHERE k IN ('tipo', 'bairro', 'condominio', 'negocio', 'quartos', 'suites', 'banheiros', 'vagas', 'area',
               'valor', 'condominio_valor', 'iptu', 'incluso', 'mobilia', 'fotos', 'detalhes')
     AND NULLIF(btrim(v), '') IS NOT NULL AND lower(btrim(v)) NOT IN ('null', 'undefined', '-');

  d := c.dados || v_novos;
  -- a pergunta que estava aberta conta como respondida (mesmo com "não sei"),
  -- desde que ele tenha dito ALGUMA coisa -- abrir a ficha não conta
  IF p_resposta AND v_novos <> '{}'::jsonb AND d ? '_perguntou' THEN
    v_resp := coalesce(d->'_respondidas', '[]'::jsonb);
    IF NOT v_resp ? (d->>'_perguntou') THEN
      d := jsonb_set(d, '{_respondidas}', v_resp || to_jsonb(d->>'_perguntou'));
    END IF;
  END IF;
  v_resp := coalesce(d->'_respondidas', '[]'::jsonb);

  IF c.codigo IS NOT NULL THEN
    SELECT * INTO i FROM imoveis WHERE codigo = c.codigo;
  END IF;

  -- tratamento: "Sr. João" / "o Sr." / "você"
  v_trat := NULLIF(btrim(l.tratamento), '');
  v_nome := NULLIF(nay_primeiro_nome(l.nome), '');
  v_pron := CASE v_trat WHEN 'Sra.' THEN 'a Sra.' WHEN 'Sr.' THEN 'o Sr.' ELSE 'você' END;
  v_pron_m := upper(left(v_pron, 1)) || substr(v_pron, 2);
  v_voc  := CASE WHEN v_trat IS NOT NULL THEN v_trat || coalesce(' ' || v_nome, '') ELSE v_nome END;

  v_aluga := CASE WHEN v_tipo = 'atualizar' THEN true ELSE coalesce(d->>'negocio', '') !~* 'vend' OR coalesce(d->>'negocio', '') ~* 'amb|alug|loca' END;
  v_cond  := coalesce(NULLIF(btrim(d->>'condominio'), ''), i.condominio_nome) IS NOT NULL
             OR coalesce(d->>'tipo', i.tipo, '') ~* 'apart|condom|flat|cobertura|sala';

  -- o que ainda falta, NA ORDEM do roteiro (grupo respondido não volta)
  v_falta := ARRAY[]::text[];
  IF v_tipo = 'novo' AND NOT v_resp ? 'local' AND (d->>'tipo' IS NULL OR coalesce(d->>'bairro', d->>'condominio') IS NULL) THEN
    v_falta := v_falta || 'local'::text;
  END IF;
  IF v_tipo = 'novo' AND NOT v_resp ? 'negocio' AND d->>'negocio' IS NULL THEN
    v_falta := v_falta || 'negocio'::text;
  END IF;
  IF NOT v_resp ? 'comodos' AND (coalesce(d->>'quartos', i.quartos::text) IS NULL
                                 OR coalesce(d->>'banheiros', i.banheiros::text) IS NULL
                                 OR coalesce(d->>'vagas', i.vagas::text) IS NULL) THEN
    v_falta := v_falta || 'comodos'::text;
  END IF;
  IF NOT v_resp ? 'area' AND coalesce(d->>'area', i.area_util::text, i.area_total::text) IS NULL THEN
    v_falta := v_falta || 'area'::text;
  END IF;
  IF NOT v_resp ? 'valor' AND coalesce(d->>'valor', CASE WHEN v_tipo = 'atualizar' THEN l.valor_locacao_pedido END) IS NULL THEN
    v_falta := v_falta || 'valor'::text;
  END IF;
  IF NOT v_resp ? 'taxas' AND (d->>'iptu' IS NULL OR (v_cond AND d->>'condominio_valor' IS NULL) OR (v_aluga AND d->>'incluso' IS NULL)) THEN
    v_falta := v_falta || 'taxas'::text;
  END IF;
  IF v_aluga AND NOT v_resp ? 'mobilia' AND coalesce(d->>'mobilia', CASE WHEN v_tipo = 'atualizar' THEN i.mobilia END) IS NULL THEN
    v_falta := v_falta || 'mobilia'::text;
  END IF;
  IF NOT v_resp ? 'fotos' AND d->>'fotos' IS NULL AND jsonb_array_length(c.fotos) = 0 THEN
    v_falta := v_falta || 'fotos'::text;
  END IF;

  v_prox := v_falta[1];
  v_frase := CASE v_prox
    WHEN 'local'   THEN 'É casa ou apartamento? E em qual bairro ou condomínio fica?'
    WHEN 'negocio' THEN v_pron_m || ' quer alugar ou vender esse imóvel?'
    WHEN 'comodos' THEN 'Quantos quartos (e quantas suítes), banheiros e vagas de garagem ele tem?'
    WHEN 'area'    THEN 'E a área, ' || v_pron || ' sabe mais ou menos quantos metros quadrados?'
    WHEN 'valor'   THEN CASE WHEN v_tipo = 'atualizar'
                              THEN coalesce(v_voc || ', ', '') || v_pron || ' pode me atualizar o valor do imóvel para locação?'
                              WHEN v_aluga AND coalesce(d->>'negocio', '') ~* 'amb'
                              THEN 'E quais valores ' || v_pron || ' quer pedir, no aluguel e na venda?'
                              WHEN v_aluga THEN 'E qual valor ' || v_pron || ' quer pedir no aluguel?'
                              ELSE 'E qual valor ' || v_pron || ' quer pedir na venda?' END
    WHEN 'taxas'   THEN CASE WHEN v_cond AND v_aluga THEN 'E o condomínio e o IPTU, estão em quanto? O aluguel já inclui algum deles?'
                              WHEN v_aluga THEN 'E o IPTU, sabe me dizer o valor? O aluguel já inclui alguma coisa, como água ou IPTU?'
                              WHEN v_cond THEN 'E o condomínio e o IPTU, estão em quanto?'
                              ELSE 'E o IPTU, sabe me dizer o valor?' END
    WHEN 'mobilia' THEN 'Ele está mobiliado, semimobiliado ou sem mobília?'
    WHEN 'fotos'   THEN v_pron_m || ' pode me enviar as fotos do imóvel?'
    END;

  IF v_prox IS NULL THEN
    UPDATE captacao_cadastro SET dados = d - '_perguntou', estado = 'pronto', atualizado_em = now() WHERE id = c.id;
    RETURN CASE WHEN v_tipo = 'atualizar'
      THEN 'ficha do imovel completa (o Tel confere e aplica). agradeca em uma linha e va para a ETAPA 4: pergunte se ' || v_pron
           || ' tem algum outro imovel alem desse que queira vender ou alugar.'
      ELSE 'ficha do imovel novo completa (o Tel confere e cadastra). agradeca em uma linha e chame encerrar_conversa -- a menos que '
           || v_pron || ' fale de mais um imovel: ai chame guardar_outro_imovel de novo.' END;
  END IF;

  UPDATE captacao_cadastro SET dados = jsonb_set(d, '{_perguntou}', to_jsonb(v_prox)), atualizado_em = now() WHERE id = c.id;
  RETURN 'anotado na ficha do imovel' || CASE WHEN v_tipo = 'novo' THEN ' novo' ELSE '' END
         || '. agora pergunte isto, com estas palavras, UMA pergunta so (pode comecar com "Certo." ou "Entendi."): "'
         || v_frase || '". quando ' || v_pron || ' responder, chame guardar_ficha com o que disse'
         || ' (se nao souber ou nao quiser dizer, passe "nao sabe" no campo perguntado).';
END $$;

-- Os 13 imóveis novos que os donos citaram de 09 a 17/09 e ficaram só como
-- frase: entram no painel como ficha pronta, para o Tel decidir.
INSERT INTO captacao_cadastro (lead_id, tipo, dados, estado, criado_em)
SELECT x.lead_id, 'novo',
       jsonb_build_object('detalhes', x.descricao, 'negocio', x.negocio, '_origem', 'citado antes de 28/09 (captacao_imoveis_extra ' || x.id || ')'),
       'pronto', x.criado_em
  FROM captacao_imoveis_extra x
 WHERE NOT coalesce(x.curado, false)
   AND NOT EXISTS (SELECT 1 FROM captacao_cadastro c WHERE c.dados->>'_origem' LIKE '%captacao_imoveis_extra ' || x.id || ')');

COMMIT;
