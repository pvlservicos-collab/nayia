-- 370 -- A NAY PROPRIETÁRIOS DA OLX: o roteiro do Pedro para o dono que anunciou na OLX, pelo número oficial
--
-- Pedro, 14/10/2026, com o "SCRIPT APÓS OLX": "monta uma nay cópia da nay captação que atende na api oficial, mas essa
-- vai funcionar captando os proprietários da OLX, a gente já vai ter o nome e número deles, e algumas informações do
-- imóvel, então o que essa deve fazer é checar o resto conforme aí no roteiro, o nome dela Nay proprietários da OLX
-- ... quero as mesmas regras gerais da que fala com os proprietários hoje, como parar quando um humano assume ... ativa
-- ela primeiramente para o meu número 96991712835 com todas as perguntas".
--
-- COMO ELA MORA: dentro do serviço nay-captacao (as regras gerais vêm de graça: o silêncio de 20 s, um balão por vez,
-- "gente escreveu pelo CRM = ela cala", a escalada ao Tel, o SILENCIO depois da despedida). O lead é um lead comum de
-- `captacao_leads`; o que o faz ser "da OLX" é ter linha em `captacao_olx`, com o anúncio e as respostas.
-- O serviço troca, para esse lead, o prompt e as ferramentas (nay-captacao/captacao/olx.py).
--
-- O ROTEIRO (o do Pedro, por perfil), uma pergunta por vez, e SÓ o que o anúncio ainda não diz:
--   VENDA   · apto escada:     condomínio, taxa, lances de escada (não se for térreo), bloco, sol da sala, 6%
--           · apto elevador:   condomínio, taxa, andar, torre, sol da sala, 6%
--           · casa condomínio: condomínio, metragem do terreno, taxa, número da casa, sol da sala, 6%
--           · casa via pública: metragem do terreno, endereço, sol da sala, 6%
--   LOCAÇÃO · igual, com o IPTU depois da taxa, e no lugar dos 6% "no valor de R$ X está incluso o condomínio?"
--             (casa via pública não tem essa)
--   depois, sempre: outros imóveis para vender ou alugar, e a indicação ("demanda alta ... nesse final de ano").
--   Apartamento sem saber se o prédio tem elevador: a primeira pergunta depois do condomínio é essa.
-- Os 6%: "não, tem que acrescentar" -> "Tudo bem, podemos trabalhar com uma margem de 10% a mais"; até 5% de honorários
-- aceitamos; menos que isso vai para o Pedro (escalada).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE captacao_olx (
  lead_id      bigint PRIMARY KEY,
  codigo       integer,
  anuncio      jsonb NOT NULL DEFAULT '{}'::jsonb,
  respostas    jsonb NOT NULL DEFAULT '{}'::jsonb,
  aberto_em    timestamptz,          -- quando o modelo de abertura saiu (o status do lead nem sempre pode voltar a 'novo')
  abertura_tentada_em timestamptz,
  criado_em    timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE captacao_olx IS '370: o lead da captação que é dono de anúncio da OLX (a "Nay proprietários da OLX"): o anúncio que já temos e as respostas do roteiro do Pedro. Ter linha aqui troca o prompt e as ferramentas do lead no nay-captacao.';
COMMENT ON COLUMN captacao_olx.anuncio IS 'o que já sabemos do imóvel (do cadastro importado da OLX): tipo, negócio, valor, condomínio, taxa, IPTU, andar, sol, áreas, endereço, título e descrição';
COMMENT ON COLUMN captacao_olx.respostas IS '{campo: o que o dono disse}, campo = condominio_nome, elevador, taxa_condominio, iptu, lances_escada, bloco, andar, torre, metragem_terreno, numero_casa, endereco, sol, honorarios, condominio_incluso, outros, outros_detalhe, indicacao';

INSERT INTO captacao_config (chave, valor) VALUES
  ('olx_abertura_modelos', 'olx_proprietario_abertura_01,olx_proprietario_abertura_02'),
  ('olx_telefones', '5596991712835')
ON CONFLICT (chave) DO NOTHING;

-- o anúncio, do cadastro do imóvel importado da OLX
CREATE FUNCTION public.captacao_olx_anuncio(p_codigo integer) RETURNS jsonb
 LANGUAGE sql STABLE SET search_path TO 'public'
AS $function$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'codigo', i.codigo, 'tipo', i.tipo, 'titulo', coalesce(i.extras->>'olx_titulo', i.extras->>'titulo'),
    'negocio', CASE WHEN coalesce(i.valor_aluguel, 0) > 0 AND coalesce(i.valor_venda, 0) = 0 THEN 'locacao' ELSE 'venda' END,
    'valor_venda', nullif(i.valor_venda, 0), 'valor_aluguel', nullif(i.valor_aluguel, 0),
    'condominio', nullif(btrim(coalesce(i.condominio_nome, '')), ''), 'bairro', i.bairro,
    'taxa_condominio', nullif(i.taxa_condominio, 0), 'iptu', nullif(i.iptu, 0),
    'andar', nullif(btrim(coalesce(i.andar, '')), ''), 'sol', nullif(btrim(coalesce(i.sol, '')), ''),
    'area_util', nullif(i.area_util, 0), 'area_total', nullif(i.area_total, 0),
    'logradouro', nullif(btrim(coalesce(i.logradouro, '')), ''), 'numero', nullif(btrim(coalesce(i.numero, '')), ''),
    'quartos', i.quartos, 'elevador', (SELECT cf.elevador FROM condominio_ficha cf WHERE cf.condominio_id = i.condo_id),
    'descricao', left(i.descricao, 1500), 'olx_id', i.extras->>'olx_id'))
    FROM imoveis i WHERE i.codigo = p_codigo;
$function$;

-- o perfil do roteiro: negócio, grupo (ap, casa_cond, casa_rua, outro), elevador (sim, nao ou desconhecido) e térreo
CREATE FUNCTION public.captacao_olx_perfil(p_lead bigint) RETURNS jsonb
 LANGUAGE plpgsql STABLE SET search_path TO 'public'
AS $function$
DECLARE
  o  captacao_olx;
  a  jsonb;
  r  jsonb;
  t  text;
  d  text;
  v_grupo text;
  v_elev  text;
  v_condo text;
BEGIN
  SELECT * INTO o FROM captacao_olx WHERE lead_id = p_lead;
  IF o.lead_id IS NULL THEN RETURN NULL; END IF;
  a := o.anuncio; r := o.respostas;
  t := lower(nay_sem_acento(coalesce(a->>'tipo', '')));
  d := lower(nay_sem_acento(coalesce(a->>'titulo', '') || ' ' || coalesce(a->>'descricao', '')));
  v_condo := a->>'condominio';
  IF v_condo IS NOT NULL AND (v_condo ~* 'n[aã]o identificad' OR lower(nay_sem_acento(v_condo)) ~ '^(casa|predio|apartamento|lote|terreno)( em via publica)?$') THEN
    v_condo := NULL;
  END IF;
  v_grupo := CASE
    WHEN t ~ '^(apartamento|cobertura|flat|kitnet|kitinete|loft|studio)' THEN 'ap'
    WHEN t ~ '^(casa|sobrado)' AND (t ~ 'condominio' OR v_condo IS NOT NULL) AND t !~ 'via publica' THEN 'casa_cond'
    WHEN t ~ '^(casa|sobrado)' THEN 'casa_rua'
    ELSE 'outro' END;
  v_elev := CASE
    WHEN r ? 'elevador' THEN CASE WHEN lower(nay_sem_acento(r->>'elevador')) ~ '(^|\W)(nao|escada|sem elevador)' THEN 'nao' ELSE 'sim' END
    WHEN lower(nay_sem_acento(coalesce(a->>'elevador', ''))) ~ '^sim' THEN 'sim'
    WHEN lower(nay_sem_acento(coalesce(a->>'elevador', ''))) ~ '^nao' THEN 'nao'
    WHEN d ~ '(sem elevador|nao (tem|possui) elevador|de escada)' THEN 'nao'
    WHEN d ~ 'elevador' THEN 'sim'
    ELSE 'desconhecido' END;
  RETURN jsonb_build_object(
    'negocio', coalesce(a->>'negocio', 'venda'), 'grupo', v_grupo, 'elevador', v_elev, 'condominio', v_condo,
    'terreo', (lower(nay_sem_acento(coalesce(a->>'andar', ''))) ~ '^(0|t|terreo)' OR d ~ '\mterreo\M'),
    'valor', CASE WHEN coalesce(a->>'negocio', 'venda') = 'locacao' THEN a->'valor_aluguel' ELSE a->'valor_venda' END);
END $function$;

-- "o Sr." / "a Sra." / "você" -- e com maiúscula, para começar a frase
CREATE FUNCTION public.captacao_olx_pronome(p_tratamento text, p_maiuscula boolean) RETURNS text
 LANGUAGE sql IMMUTABLE
AS $function$
  SELECT CASE WHEN p_tratamento = 'Sr.' THEN CASE WHEN p_maiuscula THEN 'O Sr.' ELSE 'o Sr.' END
              WHEN p_tratamento = 'Sra.' THEN CASE WHEN p_maiuscula THEN 'A Sra.' ELSE 'a Sra.' END
              ELSE CASE WHEN p_maiuscula THEN 'Você' ELSE 'você' END END;
$function$;

-- a PRÓXIMA pergunta do roteiro para este telefone: {campo, pergunta} ou {fim: true}
CREATE FUNCTION public.captacao_olx_proxima(p_telefone text) RETURNS jsonb
 LANGUAGE plpgsql STABLE SET search_path TO 'public'
AS $function$
DECLARE
  l      captacao_leads;
  o      captacao_olx;
  p      jsonb;
  a      jsonb;
  r      jsonb;
  v_loc  boolean;
  g      text;
  e      text;
  campos text[];
  c      text;
  v_tr   text;
  v_valor text;
  v_sim  boolean;
BEGIN
  SELECT * INTO l FROM captacao_leads WHERE telefone_chave = nay_fone_chave(p_telefone);
  SELECT * INTO o FROM captacao_olx WHERE lead_id = l.id;
  IF o.lead_id IS NULL THEN RETURN NULL; END IF;
  p := captacao_olx_perfil(l.id); a := o.anuncio; r := o.respostas;
  v_loc := p->>'negocio' = 'locacao'; g := p->>'grupo'; e := p->>'elevador';
  v_tr := l.tratamento;

  -- a ordem do roteiro do Pedro, por perfil
  campos := ARRAY['condominio_nome'];
  IF g = 'ap' AND e = 'desconhecido' THEN campos := array_append(campos, 'elevador'); END IF;
  IF g <> 'casa_rua' THEN campos := campos || CASE WHEN g = 'casa_cond' THEN ARRAY['metragem_terreno', 'taxa_condominio'] ELSE ARRAY['taxa_condominio'] END; END IF;
  IF v_loc THEN campos := array_append(campos, 'iptu'); END IF;
  IF g = 'ap' AND e = 'nao' THEN campos := campos || ARRAY['lances_escada', 'bloco']; END IF;
  IF g = 'ap' AND e = 'sim' THEN campos := campos || ARRAY['andar', 'torre']; END IF;
  IF g = 'casa_cond' THEN campos := array_append(campos, 'numero_casa'); END IF;
  IF g = 'casa_rua' THEN campos := ARRAY['metragem_terreno'] || CASE WHEN v_loc THEN ARRAY['iptu'] ELSE '{}'::text[] END || ARRAY['endereco']; END IF;
  IF g <> 'outro' THEN campos := array_append(campos, 'sol'); END IF;
  IF NOT v_loc THEN campos := array_append(campos, 'honorarios');
  ELSIF g <> 'casa_rua' THEN campos := array_append(campos, 'condominio_incluso'); END IF;
  campos := campos || ARRAY['outros', 'outros_detalhe', 'indicacao'];

  FOREACH c IN ARRAY campos LOOP
    CONTINUE WHEN r ? c;
    -- o que o anúncio já diz não se pergunta
    CONTINUE WHEN c = 'condominio_nome' AND (p->>'condominio' IS NOT NULL OR g = 'casa_rua');
    CONTINUE WHEN c = 'taxa_condominio' AND a ? 'taxa_condominio';
    CONTINUE WHEN c = 'iptu' AND a ? 'iptu';
    CONTINUE WHEN c = 'andar' AND a ? 'andar';
    CONTINUE WHEN c = 'lances_escada' AND (p->>'terreo')::boolean;
    CONTINUE WHEN c = 'sol' AND a ? 'sol';
    CONTINUE WHEN c = 'metragem_terreno' AND a ? 'area_total';
    CONTINUE WHEN c = 'endereco' AND a ? 'logradouro' AND a ? 'numero';
    -- o detalhe do outro imóvel só existe quando ele disse que tem
    IF c = 'outros_detalhe' THEN
      v_sim := r ? 'outros' AND lower(nay_sem_acento(r->>'outros')) !~ '^\s*(nao|no momento nao|so esse|so este|por enquanto nao|nenhum|tenho nao)';
      CONTINUE WHEN NOT v_sim;
    END IF;
    v_valor := CASE WHEN p->'valor' IS NOT NULL AND p->>'valor' <> '' THEN
                 'R$ ' || replace(to_char(round((p->>'valor')::numeric), 'FM999,999,999'), ',', '.') END;
    RETURN jsonb_build_object('campo', c, 'pergunta', CASE c
      WHEN 'condominio_nome'   THEN 'Qual é o nome do condomínio?'
      WHEN 'elevador'          THEN 'O prédio tem elevador ou é de escada?'
      WHEN 'taxa_condominio'   THEN 'Qual o valor da taxa de condomínio?'
      WHEN 'iptu'              THEN captacao_olx_pronome(v_tr, true) || ' se recorda do valor do IPTU?'
      WHEN 'lances_escada'     THEN 'Quantos lances de escada até o apartamento?'
      WHEN 'bloco'             THEN 'Qual o bloco do seu apartamento?'
      WHEN 'andar'             THEN 'Qual o andar do seu apartamento?'
      WHEN 'torre'             THEN 'Qual a torre do seu apartamento?'
      WHEN 'metragem_terreno'  THEN 'Qual a metragem do seu terreno?'
      WHEN 'numero_casa'       THEN 'Qual o número da casa?'
      WHEN 'endereco'          THEN 'Qual o endereço da casa?'
      WHEN 'sol'               THEN 'A sua sala pega o sol da manhã ou da tarde?'
      WHEN 'honorarios'        THEN CASE WHEN v_valor IS NOT NULL
                                         THEN 'No valor de ' || v_valor || ', já estão inclusos os honorários de 6% de corretagem?'
                                         ELSE 'No valor que ' || captacao_olx_pronome(v_tr, false) || ' está pedindo, já estão inclusos os honorários de 6% de corretagem?' END
      WHEN 'condominio_incluso' THEN 'No valor que ' || captacao_olx_pronome(v_tr, false) || ' está pedindo'
                                      || coalesce(', de ' || v_valor, '') || ', está inclusa a taxa de condomínio?'
      WHEN 'outros'            THEN captacao_olx_pronome(v_tr, true) || ' tem outros imóveis que queira vender ou alugar?'
      WHEN 'outros_detalhe'    THEN 'Qual é o outro imóvel e onde fica?'
      WHEN 'indicacao'         THEN 'Estamos com uma demanda alta de clientes querendo comprar imóveis nesse final de ano. '
                                    || captacao_olx_pronome(v_tr, true) || ' teria alguém para indicar que queira vender ou alugar?'
    END);
  END LOOP;
  RETURN jsonb_build_object('fim', true);
END $function$;

-- guarda a resposta e devolve a ordem para a Nay (a próxima pergunta, com as palavras certas)
CREATE FUNCTION public.captacao_olx_guardar(p_telefone text, p_campo text, p_valor text) RETURNS text
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_lead bigint;
  v_campo text := lower(btrim(coalesce(p_campo, '')));
  v_valor text := btrim(coalesce(p_valor, ''));
  v_prox jsonb;
  v_antes text := '';
  v_pct numeric;
  v_txt text := lower(nay_sem_acento(coalesce(p_valor, '')));
BEGIN
  SELECT l.id INTO v_lead FROM captacao_leads l JOIN captacao_olx o ON o.lead_id = l.id WHERE l.telefone_chave = nay_fone_chave(p_telefone);
  IF v_lead IS NULL THEN RETURN 'ERRO: este proprietario nao e da OLX'; END IF;
  IF v_campo NOT IN ('condominio_nome', 'elevador', 'taxa_condominio', 'iptu', 'lances_escada', 'bloco', 'andar', 'torre',
                     'metragem_terreno', 'numero_casa', 'endereco', 'sol', 'honorarios', 'condominio_incluso', 'outros',
                     'outros_detalhe', 'indicacao') THEN
    RETURN 'ERRO: campo desconhecido (' || v_campo || '). Use o campo da pergunta que voce fez.';
  END IF;
  IF v_valor = '' THEN v_valor := 'nao sabe'; END IF;

  -- OS 6% (o roteiro do Pedro): menos de 5% vai para o Pedro; "tem que acrescentar" ganha a margem de 10%
  IF v_campo = 'honorarios' THEN
    v_pct := (SELECT replace((regexp_match(v_txt, '(\d+(?:[.,]\d+)?)\s*(%|por cento)'))[1], ',', '.')::numeric);
    IF v_pct IS NOT NULL AND v_pct < 5 THEN
      UPDATE captacao_olx SET respostas = respostas || jsonb_build_object(v_campo, v_valor), atualizado_em = now() WHERE lead_id = v_lead;
      RETURN 'ele propos honorarios ABAIXO de 5% (' || v_valor || '): isso e com o Pedro. Chame escalar_ao_tel com assunto '
             || '"honorarios abaixo de 5%" e disse = o que ele escreveu, e responda SILENCIO. Nao comente o percentual.';
    END IF;
    IF v_txt ~ '(nao|acrescent|por fora|liquido|em cima|fora)' AND v_txt !~ 'inclus' THEN
      v_antes := 'ele disse que os 6% NAO estao inclusos: comece a resposta com exatamente "Tudo bem, podemos trabalhar com uma margem de 10% a mais." ';
    END IF;
  END IF;

  UPDATE captacao_olx SET respostas = respostas || jsonb_build_object(v_campo, v_valor), atualizado_em = now() WHERE lead_id = v_lead;
  UPDATE captacao_leads SET pergunta_pendente = NULL, atualizado_em = now() WHERE id = v_lead;
  v_prox := captacao_olx_proxima(p_telefone);
  IF coalesce((v_prox->>'fim')::boolean, false) THEN
    RETURN 'anotado. ' || v_antes || 'O roteiro acabou: agradeca em uma linha ("Ok, obrigada!" ou "Certo, obrigada pela informacao!") '
           || 'e chame encerrar_conversa com motivo = concluido. Nao faca mais nenhuma pergunta.';
  END IF;
  RETURN 'anotado. ' || v_antes || 'Agora, na MESMA resposta, depois de uma confirmacao curta ("Certo." / "Entendi, anotei aqui."), '
         || 'faca a proxima pergunta com EXATAMENTE estas palavras (campo ' || (v_prox->>'campo') || '): "' || (v_prox->>'pergunta') || '"';
END $function$;

-- encerra a conversa: só depois do roteiro inteiro (menos quem pediu para parar ou é número errado)
CREATE FUNCTION public.captacao_olx_encerrar(p_telefone text, p_motivo text) RETURNS text
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_lead bigint;
  v_motivo text := lower(btrim(coalesce(p_motivo, 'concluido')));
  v_prox jsonb;
BEGIN
  SELECT l.id INTO v_lead FROM captacao_leads l JOIN captacao_olx o ON o.lead_id = l.id WHERE l.telefone_chave = nay_fone_chave(p_telefone);
  IF v_lead IS NULL THEN RETURN 'ERRO: este proprietario nao e da OLX'; END IF;
  IF v_motivo NOT IN ('opt_out', 'numero_errado', 'nao_e_o_dono', 'parou_de_responder') THEN
    v_prox := captacao_olx_proxima(p_telefone);
    IF NOT coalesce((v_prox->>'fim')::boolean, false) THEN
      RETURN 'NAO encerrei: ainda falta o roteiro. Faca agora, com EXATAMENTE estas palavras, esta pergunta (campo '
             || (v_prox->>'campo') || '): "' || (v_prox->>'pergunta') || '"';
    END IF;
  END IF;
  UPDATE captacao_leads
     SET etapa = 'concluido', status = 'concluido', motivo_fim = 'olx: ' || v_motivo, fechado_em = now(),
         opt_out = opt_out OR v_motivo = 'opt_out', pergunta_pendente = NULL, atualizado_em = now()
   WHERE id = v_lead;
  RETURN 'encerrado. Nao faca mais perguntas. Se ele mandar mais um ok/obrigado depois da sua despedida, responda SILENCIO.';
END $function$;

-- põe um dono da OLX na captação: o lead (pelo telefone dele) e o anúncio (do imóvel importado). Devolve o lead.
-- `p_telefone` e `p_nome` são para o TESTE (o anúncio de um imóvel, emprestado ao telefone do Pedro); sem eles,
-- valem o dono e o telefone do cadastro do imóvel.
CREATE FUNCTION public.captacao_olx_novo(p_codigo integer, p_telefone text DEFAULT NULL, p_nome text DEFAULT NULL) RETURNS bigint
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_tel  text;
  v_nome text;
  v_prop integer;
  v_lead bigint;
BEGIN
  SELECT nay_fone_com_ddi(p.telefone), p.nome, p.id INTO v_tel, v_nome, v_prop
    FROM imoveis i LEFT JOIN imovel_privado ip ON ip.codigo = i.codigo
    LEFT JOIN proprietarios p ON p.id = coalesce(ip.proprietario_id, i.proprietario_id)
   WHERE i.codigo = p_codigo;
  v_tel := regexp_replace(coalesce(p_telefone, v_tel, ''), '\D', '', 'g');
  v_nome := coalesce(nullif(btrim(p_nome), ''), v_nome);
  IF length(v_tel) NOT BETWEEN 12 AND 13 THEN RAISE EXCEPTION 'sem telefone utilizável para o imóvel %', p_codigo; END IF;
  SELECT id INTO v_lead FROM captacao_leads WHERE telefone_chave = nay_fone_chave(v_tel);
  IF v_lead IS NULL THEN
    INSERT INTO captacao_leads (telefone, nome, tratamento, proprietario_id, codigo, condominio, bairro, tipo_imovel, quem_importou, status, etapa)
    SELECT v_tel, v_nome, nay_tratamento_por_nome(v_nome), CASE WHEN p_telefone IS NULL THEN v_prop END, i.codigo::text,
           i.condominio_nome, i.bairro, i.tipo, 'olx (Nay proprietários da OLX)', 'novo', 'novo'
      FROM imoveis i WHERE i.codigo = p_codigo
    RETURNING id INTO v_lead;
  END IF;
  INSERT INTO captacao_olx (lead_id, codigo, anuncio) VALUES (v_lead, p_codigo, captacao_olx_anuncio(p_codigo))
  ON CONFLICT (lead_id) DO UPDATE SET codigo = excluded.codigo, anuncio = excluded.anuncio, respostas = '{}'::jsonb,
                                       aberto_em = NULL, abertura_tentada_em = NULL, atualizado_em = now();
  RETURN v_lead;
END $function$;

-- ATIVA PARA O TELEFONE DO PEDRO (o lead de teste da captação, 835): o anúncio de um apartamento de VENDA importado da
-- OLX; o anúncio emprestado perde condomínio, elevador, andar, sol, taxa e IPTU para ele ouvir TODAS as perguntas.
-- O modelo de abertura sai quando a Meta aprovar (nay-captacao: olx.abrir, marca captacao_olx.aberto_em).
DO $$
DECLARE v_cod integer; v_lead bigint;
BEGIN
  SELECT i.codigo INTO v_cod FROM imoveis i
   WHERE i.origem = 'olx' AND i.tipo ~* '^apartamento' AND coalesce(i.valor_venda, 0) > 0
   ORDER BY i.codigo DESC LIMIT 1;
  v_lead := captacao_olx_novo(v_cod, '5596991712835', 'Pedro');
  -- "com todas as perguntas": o anúncio do teste fica só com tipo, negócio, valor e bairro, para o roteiro inteiro sair
  UPDATE captacao_olx SET anuncio = anuncio - 'condominio' - 'elevador' - 'andar' - 'sol' - 'taxa_condominio' - 'iptu' - 'area_total' - 'descricao' - 'titulo'
   WHERE lead_id = v_lead;
  UPDATE captacao_leads SET situacao = NULL, contrato_ate = NULL, valor_locacao_pedido = NULL, etapa = 'aguardando_situacao',
         tem_outro_imovel = false, quer_vender = false, valor_venda_pedido = NULL, motivo_fim = NULL, fechado_em = NULL,
         pergunta_pendente = NULL, status = 'novo', respondeu_em = NULL, humano_assumiu_em = NULL, humano_motivo = NULL,
         canal = 'oficial'
   WHERE id = v_lead;
  RAISE NOTICE 'Nay proprietários da OLX ligada para o lead % (telefone do Pedro), com o anúncio do imóvel %', v_lead, v_cod;
END $$;

REVOKE ALL ON FUNCTION public.captacao_olx_guardar(text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.captacao_olx_encerrar(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.captacao_olx_novo(integer, text, text) FROM PUBLIC;

COMMIT;
