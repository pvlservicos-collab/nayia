-- 191p -- gerado por 191_remendos.py a partir do pg_proc vivo (29/09/2026).
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.nai_resposta_da_base(p_codigo integer, p_pergunta text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  i      imoveis;
  q      text := lower(unaccent(coalesce(p_pergunta, '')));
  car    text;
  des    text;
  dorig  text;
  r      text[] := '{}';   -- a resposta: o primeiro e a afirmacao, o resto vira lista
  linhas text[] := '{}';
  v_fr   text;
  v_inc  text;
  v_out  text;
  f_q    text;             -- a ficha, que sai listada depois da afirmacao
  f_b    text;
  f_v    text;
  f_a    text;
  f_an   text;
  busca  text[] := ARRAY['piscina', 'academia', 'elevador', 'portaria', 'churrasqueira', 'salao de festa', 'playground',
                         'varanda', 'sacada', 'gourmet', 'ar-condicionado', 'ar condicionado', 'area de lazer', 'quadra',
                         'sauna', 'quintal', 'jardim', 'interfone', 'cerca eletrica', 'seguranca 24'];
  exibe  text[] := ARRAY['piscina', 'academia', 'elevador', 'portaria', 'churrasqueira', 'salão de festas', 'playground',
                         'varanda', 'sacada', 'espaço gourmet', 'ar-condicionado', 'ar-condicionado', 'área de lazer', 'quadra',
                         'sauna', 'quintal', 'jardim', 'interfone', 'cerca elétrica', 'segurança 24h'];
  n      int;
  v_fin  text;   -- 191: a ficha do anuncio
  v_per  text;
  v_gar  text;
  v_esc  text;
  v_tx   text;
BEGIN
  IF p_codigo IS NULL OR btrim(q) = '' THEN RETURN NULL; END IF;
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL OR coalesce(i.e_parceiro, false) THEN RETURN NULL; END IF;
  -- 191: a FICHA DO ANUNCIO entra aqui -- caracteristicas do imovel e do
  -- condominio, descricao e observacoes (sem numero de unidade). Antes era so
  -- o banco, e 117 dos 260 imoveis no ar nao tinham descricao nenhuma.
  car   := lower(unaccent(array_to_string(nai_ficha_caracteristicas(p_codigo), ', ')));
  dorig := coalesce(nai_ficha_texto_livre(p_codigo), '');
  des   := lower(unaccent(dorig));
  v_inc := lower(unaccent(coalesce(nai_ficha_valor(p_codigo, 'incluso no aluguel'), '')));  -- 191

  -- A ficha basica, escrita uma vez: serve de resposta quando ele pergunta
  -- isso, e de lista depois da afirmacao quando ele pergunta outra coisa.
  f_q := CASE WHEN coalesce(i.quartos, 0) > 0 THEN
           'tem ' || i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END ||
           CASE WHEN coalesce(i.suites, 0) > 0 THEN ', sendo ' || i.suites || CASE WHEN i.suites = 1 THEN ' suíte' ELSE ' suítes' END ELSE '' END END;
  f_b := CASE WHEN coalesce(i.banheiros, 0) > 0 THEN
           'tem ' || i.banheiros || CASE WHEN i.banheiros = 1 THEN ' banheiro' ELSE ' banheiros' END END;
  -- VAGAS: NULL em vagas_cobertas e "nao sei", nao "nenhuma" -- mesma regra do card.
  f_v := CASE
           WHEN coalesce(i.vagas, 0) = 0 AND coalesce(i.vagas_cobertas, 0) > 0
             THEN 'tem ' || i.vagas_cobertas || CASE WHEN i.vagas_cobertas = 1 THEN ' vaga coberta' ELSE ' vagas cobertas' END
           WHEN coalesce(i.vagas, 0) = 0 THEN NULL
           WHEN i.vagas_cobertas IS NULL THEN 'tem ' || i.vagas || CASE WHEN i.vagas = 1 THEN ' vaga de garagem' ELSE ' vagas de garagem' END
           WHEN i.vagas_cobertas = 0 THEN 'tem ' || i.vagas || CASE WHEN i.vagas = 1 THEN ' vaga descoberta' ELSE ' vagas descobertas' END
           WHEN i.vagas_cobertas >= i.vagas THEN 'tem ' || i.vagas || CASE WHEN i.vagas = 1 THEN ' vaga coberta' ELSE ' vagas cobertas' END
           ELSE 'tem ' || i.vagas || ' vagas, sendo ' || i.vagas_cobertas || CASE WHEN i.vagas_cobertas = 1 THEN ' coberta' ELSE ' cobertas' END END;
  f_a := CASE WHEN coalesce(i.area_util, 0) > 0 THEN 'tem ' || trim(to_char(i.area_util, 'FM999990')) || ' m²' END;
  f_an := CASE WHEN coalesce(i.andar, '') <> '' THEN
            CASE WHEN i.andar ~ '^\d+$' THEN 'fica no ' || i.andar || 'º andar' ELSE 'fica no andar ' || i.andar END END;

  -- FOI PARA O GRUPO? (Tel, 16/09). O corretor Leonan encaminhou o card do
  -- Acquarelle no privado e perguntou "Nay, esse ta no grupo da EASY?". Ela
  -- escalou ao Tel e a conversa parou -- mas a resposta esta em `envios`: e
  -- dali que sai tudo o que foi disparado nos grupos, com a hora.
  DECLARE v_grp timestamptz;
  BEGIN
    IF q ~ '\mgrupo|grupos\M' THEN
      SELECT max(e.enviado_em) INTO v_grp FROM envios e
       WHERE e.destino = 'grupo' AND e.codigo = p_codigo::text;
      IF v_grp IS NULL THEN
        RETURN 'Esse eu ainda não mandei no grupo.';
      END IF;
      RETURN 'Mandei sim, no grupo '
             || CASE
                  WHEN (v_grp AT TIME ZONE 'America/Manaus')::date
                       = (now() AT TIME ZONE 'America/Manaus')::date
                    THEN 'hoje às ' || to_char(v_grp AT TIME ZONE 'America/Manaus', 'HH24:MI')
                  WHEN (v_grp AT TIME ZONE 'America/Manaus')::date
                       = (now() AT TIME ZONE 'America/Manaus')::date - 1
                    THEN 'ontem às ' || to_char(v_grp AT TIME ZONE 'America/Manaus', 'HH24:MI')
                  ELSE 'dia ' || to_char(v_grp AT TIME ZONE 'America/Manaus', 'DD/MM')
                END
             || '.';
    END IF;
  END;

  -- MOBILIA ("e mobiliado?", "vem com moveis?", "tem armario planejado?", "e vazio?").
  -- Duas partes: a afirmacao e o detalhe, que vira a primeira linha da lista.
  IF q ~ '(mobil|\mmovel|moveis|semi.?mob|\mvazio|equipad|planejad|armario|guarda.?roupa|geladeira|fogao|\mcama\M)' THEN
    IF lower(coalesce(i.mobilia, '')) ~ '^semi' THEN
      r := r || 'é semi-mobiliado'::text || 'tem móveis planejados e ar-condicionado'::text;
    ELSIF lower(coalesce(i.mobilia, '')) ~ '^mobiliad' THEN
      r := r || 'é mobiliado'::text || 'tem móveis, cama e tudo'::text;
    ELSIF lower(coalesce(i.mobilia, '')) ~ 'ar.condicionado' THEN
      r := r || 'não é mobiliado'::text || 'tem só o ar-condicionado'::text;
    ELSIF car ~ 'semi.?mobiliad' THEN
      r := r || 'é semi-mobiliado'::text;
    ELSIF car ~ '(sem mobilia|nao mobiliad)' THEN
      r := r || 'não é mobiliado'::text;
    ELSIF car ~ 'mobiliad' THEN
      r := r || 'é mobiliado'::text;
    END IF;
  END IF;

  IF q ~ '(quarto|dormitorio|suite)' AND f_q IS NOT NULL THEN r := r || f_q; END IF;
  IF q ~ '(banheiro|\mwc\M|lavabo|sanitario)' AND f_b IS NOT NULL THEN r := r || f_b; END IF;
  IF q ~ '(\mvaga|garagem|estacionamento|\mcarro)' AND f_v IS NOT NULL THEN r := r || f_v; END IF;
  IF q ~ '(\marea\M|metragem|tamanho|\mm2\M|\mmetros|metro quadrado)' AND f_a IS NOT NULL THEN r := r || f_a; END IF;
  IF q ~ '(\mandar|pavimento)' AND f_an IS NOT NULL THEN r := r || f_an; END IF;

  -- SOL
  IF q ~ '(\msol\M|nascente|poente|posicao do sol|lado do sol)' AND coalesce(i.sol, '') <> '' THEN
    r := r || ('é ' || lower(i.sol));
  END IF;

  -- NOME DO CONDOMINIO
  IF q ~ '(qual|nome).{0,15}(condominio|predio|residencial|edificio)' AND q !~ '(taxa|valor|\mquanto\M|preco|custa)'
     AND coalesce(nai_condominio_ok(i.condominio_nome), '') <> '' THEN
    r := r || ('fica no ' || nai_condominio_ok(i.condominio_nome));
  -- TAXA DE CONDOMINIO
  ELSIF q ~ '(taxa|condominio)' AND q ~ '(taxa|valor|\mquanto\M|preco|custa|inclus|\mpaga)' THEN
    IF v_inc ~ 'condom' THEN
      r := r || 'a taxa de condomínio já está inclusa no aluguel'::text;
    ELSIF coalesce(i.taxa_condominio, 0) > 0 THEN
      r := r || ('a taxa de condomínio é R$ ' || replace(to_char(i.taxa_condominio, 'FM999,999,990'), ',', '.'));
    ELSIF nai_ficha_valor(p_codigo, 'taxa de condominio') ~ '\d' THEN  -- 191
      v_tx := regexp_replace(regexp_replace(nai_ficha_valor(p_codigo, 'taxa de condominio'), '\s+', ' ', 'g'), ',00$', '');
      r := r || ('a taxa de condomínio é ' || v_tx);
    END IF;
  END IF;

  -- IPTU
  IF q ~ 'iptu' THEN
    IF v_inc ~ 'iptu' THEN
      r := r || 'o IPTU já está incluso no aluguel'::text;
    ELSIF coalesce(i.iptu, 0) > 0 THEN
      r := r || ('o IPTU é R$ ' || replace(to_char(i.iptu, 'FM999,999,990'), ',', '.'));
    ELSIF nai_ficha_valor(p_codigo, 'iptu') ~ '\d' THEN  -- 191
      v_tx := regexp_replace(regexp_replace(nai_ficha_valor(p_codigo, 'iptu'), '\s+', ' ', 'g'), ',00$', '');
      r := r || ('o IPTU é ' || v_tx);
    END IF;
  END IF;

  -- VALOR (aluguel / venda)
  IF q ~ '(valor|preco|\mquanto\M|aluguel|custa|mensal)' AND q !~ '(condominio|iptu|taxa)' THEN
    IF q ~ '(venda|vender|compra)' AND coalesce(i.valor_venda, 0) > 0 THEN
      r := r || ('o valor de venda é R$ ' || replace(to_char(i.valor_venda, 'FM999,999,990'), ',', '.'));
    ELSIF coalesce(i.valor_aluguel, 0) > 0 THEN
      r := r || ('o aluguel é R$ ' || replace(to_char(i.valor_aluguel, 'FM999,999,990'), ',', '.') ||
                 CASE WHEN v_inc ~ 'condom' THEN ', já com a taxa de condomínio inclusa' ELSE '' END);
    END IF;
  END IF;

  -- DISPONIBILIDADE
  IF q ~ '(disponivel|disponibilidade|ainda (tem|esta|ta)|\mlivre|alugado|\mvago\M|ja alugou)' THEN
    r := r || CASE WHEN nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
                   THEN 'está disponível' ELSE 'não está mais disponível' END;
  END IF;

  -- ONDE FICA (nunca o numero do predio, da casa ou do apartamento)
  IF q ~ '(bairro|onde fica|localiza|endereco|\mrua\M|regiao|\mzona\M)' THEN
    v_fr := concat_ws(', ',
      CASE WHEN coalesce(nai_condominio_ok(i.condominio_nome), '') <> '' THEN 'no ' || nai_condominio_ok(i.condominio_nome) END,
      CASE WHEN coalesce(nay_endereco_sem_numero(i.logradouro), '') <> '' THEN 'na ' || nay_endereco_sem_numero(i.logradouro) END,
      CASE WHEN coalesce(i.bairro, '') <> '' THEN 'bairro ' || i.bairro END);
    IF coalesce(v_fr, '') <> '' THEN r := r || ('fica ' || v_fr); END IF;
  END IF;

  -- FORMA DE PAGAMENTO (191, 29/09): SO A FICHA RESPONDE. A Nay disse ao Paulo
  -- que o Living Comfort (5664) era "somente a vista"; o anuncio diz "Aceita
  -- Financiamento? Sim". Aqui a pergunta de financiamento, de "e a vista?" e de
  -- forma de pagamento sai da linha do anuncio. Sem a linha, NULL: a
  -- ferramenta manda escalar ao Tel, e ninguem supoe.
  v_fin := nai_ficha_valor(p_codigo, 'aceita financiamento');
  IF q ~ '(financ|a vista|avista|forma de pagamento|\mpagamento|\mparcel)' AND coalesce(i.valor_venda, 0) > 0 THEN
    IF v_fin ~* '^s' THEN
      r := r || CASE WHEN q ~ '(a vista|avista)' THEN 'não precisa ser à vista: aceita financiamento'
                     ELSE 'aceita financiamento' END;
    ELSIF v_fin ~* '^n' THEN
      r := r || 'não aceita financiamento, é só à vista'::text;
    END IF;
  END IF;
  -- FGTS: so quando o anuncio fala (a frase dele)
  IF q ~ 'fgts' THEN
    v_fr := (regexp_match(dorig, '[^.!?\n]*fgts[^.!?\n]*', 'i'))[1];
    IF coalesce(btrim(v_fr), '') <> '' THEN r := r || ('sobre FGTS, o anúncio diz: "' || btrim(v_fr) || '"'); END IF;
  END IF;
  -- PERMUTA
  IF q ~ '(permuta|\mtroca\M)' THEN
    v_per := nai_ficha_valor(p_codigo, 'aceita permuta');
    IF v_per ~* '^s' THEN
      r := r || ('aceita permuta' || coalesce(' (' || lower(nai_ficha_valor(p_codigo, 'permuta')) || ')', ''));
    ELSIF v_per ~* '^n' THEN
      r := r || 'não aceita permuta'::text;
    END IF;
  END IF;
  -- GARANTIA DO ALUGUEL (fiador, caucao, seguro-fianca)
  IF q ~ '(fiador|caucao|garantia|seguro.?fianca|titulo de capitaliza|deposito)' AND coalesce(i.valor_aluguel, 0) > 0 THEN
    v_gar := nai_ficha_valor(p_codigo, 'garantia de aluguel');
    IF v_gar IS NOT NULL THEN r := r || ('a garantia do aluguel é ' || lower(v_gar)); END IF;
  END IF;
  -- LANCES DE ESCADA
  IF q ~ '(escada|lances)' THEN
    v_esc := nai_ficha_valor(p_codigo, 'lances de escada');
    IF v_esc ~ '\d' THEN r := r || ('tem ' || v_esc || CASE WHEN v_esc = '1' THEN ' lance de escada' ELSE ' lances de escada' END); END IF;
  END IF;

  -- PET: so quando o anuncio fala (a frase dele, sem numero de unidade)
  IF q ~ '(\mpet|animal|animais|cachorro|\mgato|bicho|\mcao\M)' THEN
    v_fr := (regexp_match(dorig, '[^.!?\n]*(?:\mpet|animal|animais|cachorro|gato)[^.!?\n]*', 'i'))[1];
    IF coalesce(btrim(v_fr), '') <> '' THEN r := r || ('sobre pet, o anúncio diz: "' || btrim(v_fr) || '"'); END IF;
  END IF;

  -- LAZER / CARACTERISTICAS: so afirma o que o cadastro ou o anuncio dizem
  FOR n IN 1 .. array_length(busca, 1) LOOP
    IF position(busca[n] IN q) > 0 AND (position(busca[n] IN car) > 0 OR position(busca[n] IN des) > 0)
       AND NOT (('tem ' || exibe[n]) = ANY (r)) THEN
      r := r || ('tem ' || exibe[n]);
    END IF;
  END LOOP;

  IF coalesce(array_length(r, 1), 0) = 0 THEN RETURN NULL; END IF;

  -- A AFIRMACAO (Tel, 13/09): "Sim!" so quando a pergunta e de sim ou nao --
  -- "quantos quartos?" nao se responde com "Sim!". Resposta negativa fica sem
  -- o "Sim", ela mesma ja nega.
  v_out := nai_frase_maiuscula(r[1]);
  -- "Sim!" so quando a resposta e um sim inteiro. Em "e mobiliado?" com imovel
  -- SEMI-mobiliado, "Sim! E semi-mobiliado" engana o corretor: fica so a frase.
  IF q !~ '(qual|quais|quanto|quantos|quantas|onde|como)'
     AND r[1] !~ '^n[ãa]o' AND r[1] !~ '^é semi' THEN
    v_out := 'Sim! ' || v_out;
  END IF;

  -- A LISTA: o resto do que ele perguntou, e depois a ficha do imovel.
  FOR n IN 2 .. coalesce(array_length(r, 1), 1) LOOP
    linhas := linhas || nai_frase_maiuscula(r[n]);
  END LOOP;
  FOREACH v_fr IN ARRAY ARRAY[f_q, f_b, f_v, f_a, f_an] LOOP
    IF v_fr IS NOT NULL AND NOT (v_fr = ANY (r)) THEN linhas := linhas || nai_frase_maiuscula(v_fr); END IF;
  END LOOP;

  IF coalesce(array_length(linhas, 1), 0) = 0 THEN RETURN v_out; END IF;
  RETURN v_out || E'\n\n' || array_to_string(linhas, E'\n');
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_o_que_sei_do_imovel(p_codigo text, p_pergunta text)
 RETURNS TABLE(texto_pronto text, sabe boolean, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_cod  text := NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '');
  v_base text;
  v_velho record;  -- 191
  v_ass   text;
  v_ficha text;
BEGIN
  -- A SITUACAO DO IMOVEL (Tel, 28/09/2026): disponivel -> status + card +
  -- fotos; qualquer outro status -> diz a situacao e ja lista os disponiveis
  -- do mesmo condominio (ou oferece outras opcoes perto). Parceria fica fora:
  -- quem fala de parceria e o Tel.
  IF length(v_cod) BETWEEN 3 AND 5 AND nai_pergunta_status(p_pergunta)
     AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = v_cod::int AND NOT coalesce(i.e_parceiro, false)) THEN
    RETURN QUERY SELECT s.texto_pronto, true, s.instrucao_para_voce FROM nai_status_do_imovel(v_cod::int) s;
    RETURN;
  END IF;
  IF length(v_cod) BETWEEN 3 AND 5 THEN
    v_base := nai_resposta_da_base(v_cod::int, p_pergunta);
  END IF;
  IF v_base IS NOT NULL THEN
    RETURN QUERY SELECT v_base, true,
      ('isto esta na ficha do imovel: mande o texto_pronto EXATAMENTE como veio, com as quebras de linha, ' ||
       'sem resumir, sem juntar numa frase so e sem emoji. NAO escale. NAO emende convite de visita: o sistema manda isso sozinho.')::text;
    RETURN;
  END IF;
  -- 191: o que o Tel ja respondeu deste imovel (a busca antiga) vem primeiro.
  SELECT x.texto_pronto, x.sabe, x.instrucao_para_voce INTO v_velho
    FROM nay_o_que_sei_do_imovel(p_codigo, p_pergunta) x LIMIT 1;
  IF coalesce(v_velho.sabe, false) THEN
    RETURN QUERY SELECT v_velho.texto_pronto, v_velho.sabe, v_velho.instrucao_para_voce;
    RETURN;
  END IF;
  -- ASSUNTO SENSIVEL QUE A FICHA NAO RESPONDE -> O TEL (Pedro, 29/09: "se nao
  -- tiver la claro, ela vai perguntar ao Tel e nao informar algo assim de forma
  -- errada"). Forma de pagamento, FGTS, permuta, garantia, documentacao, pet.
  v_ass := nai_assunto_sensivel(p_pergunta);
  IF v_ass IS NOT NULL AND length(v_cod) BETWEEN 3 AND 5 THEN
    RETURN QUERY SELECT NULL::text, false,
      ('ASSUNTO SENSIVEL (' || v_ass || ') QUE A FICHA DO ' || v_cod || ' NAO RESPONDE. NAO responda, NAO suponha, '
       || 'NAO diga "acho", "normalmente" nem "somente a vista": chame escalar_ao_tel com a pergunta dele e responda '
       || 'SILENCIO. O Tel responde e a resposta chega a ele.')::text;
    RETURN;
  END IF;
  -- O RESTO: A FICHA INTEIRA PARA LER (o "rag" do Pedro). Responder so com o
  -- que esta escrito; o que nao esta, sobe ao Tel.
  v_ficha := CASE WHEN length(v_cod) BETWEEN 3 AND 5 THEN nai_ficha_completa(v_cod::int) END;
  RETURN QUERY SELECT v_velho.texto_pronto, v_velho.sabe,
    (coalesce(v_velho.instrucao_para_voce, '')
     || CASE WHEN v_ficha IS NOT NULL
             THEN E'\n\nA FICHA INTEIRA DO IMOVEL -- leia antes de responder e responda SO com o que esta escrito nela. '
                  || E'O que nao esta escrito: chame escalar_ao_tel e responda SILENCIO.\n' || v_ficha
             ELSE '' END)::text;
END;
$function$;

-- o card montado do banco, como era ate a 191: vira a reserva do card da ficha
CREATE OR REPLACE FUNCTION public.nai_card_do_banco(p_codigo integer)
 RETURNS TABLE(texto_pronto text, qtd_fotos integer)
 LANGUAGE sql
 STABLE
AS $function$
  WITH b AS (
    SELECT i.*,
           CASE WHEN coalesce(nai_condominio_ok(i.condominio_nome), '') <> ''
                THEN nai_condominio_ok(i.condominio_nome)
                WHEN coalesce(i.bairro, '') = '' THEN coalesce(i.tipo, 'Imóvel ' || i.codigo)
                WHEN lower(i.bairro) ~ '^(conjunto|conj\.|cj)' THEN coalesce(i.tipo, 'Imóvel') || ' ' || i.bairro
                ELSE coalesce(i.tipo, 'Imóvel') || ' bairro ' || i.bairro END AS titulo
      FROM imoveis i WHERE i.codigo = p_codigo)
  SELECT
    CASE WHEN coalesce(b.e_parceiro, false) THEN
      '📍 ' || b.titulo || E'
• esse imovel e de parceria, nao da imob easy.'
    ELSE
      '📍 ' || b.titulo
      || CASE WHEN coalesce(b.bairro, '') <> '' AND position(lower(b.bairro) IN lower(b.titulo)) = 0
              THEN E'
• Bairro: ' || b.bairro ELSE '' END
      || CASE WHEN coalesce(b.area_util, 0) > 0 THEN E'
• ' || trim(to_char(b.area_util, 'FM999990')) || 'm2' ELSE '' END
      || CASE WHEN coalesce(b.quartos, 0) > 0 THEN E'
• ' || b.quartos || CASE WHEN b.quartos = 1 THEN ' quarto' ELSE ' quartos' END
              || CASE WHEN coalesce(b.suites, 0) > 0 THEN ' sendo ' || b.suites || CASE WHEN b.suites = 1 THEN ' suíte' ELSE ' suítes' END ELSE '' END ELSE '' END
      || CASE WHEN coalesce(b.banheiros, 0) > 0 THEN E'
• ' || b.banheiros || CASE WHEN b.banheiros = 1 THEN ' banheiro' ELSE ' banheiros' END ELSE '' END
      -- vagas: NULL em vagas_cobertas e "nao sei", nao "nenhuma" (mesma regra do publicador).
      || CASE WHEN coalesce(b.vagas, 0) = 0 AND coalesce(b.vagas_cobertas, 0) > 0
                THEN E'
• ' || b.vagas_cobertas || CASE WHEN b.vagas_cobertas = 1 THEN ' vaga coberta' ELSE ' vagas cobertas' END
              WHEN coalesce(b.vagas, 0) = 0 THEN ''
              WHEN b.vagas_cobertas IS NULL THEN E'
• ' || b.vagas || CASE WHEN b.vagas = 1 THEN ' vaga' ELSE ' vagas' END
              WHEN b.vagas_cobertas = 0 THEN E'
• ' || b.vagas || CASE WHEN b.vagas = 1 THEN ' vaga descoberta' ELSE ' vagas descobertas' END
              WHEN b.vagas_cobertas >= b.vagas THEN E'
• ' || b.vagas || CASE WHEN b.vagas = 1 THEN ' vaga coberta' ELSE ' vagas cobertas' END
              ELSE E'
• ' || b.vagas || CASE WHEN b.vagas = 1 THEN ' vaga' ELSE ' vagas' END
                   || ' sendo ' || b.vagas_cobertas || CASE WHEN b.vagas_cobertas = 1 THEN ' vaga coberta' ELSE ' vagas cobertas' END END
      || CASE WHEN lower(coalesce(b.sol, '')) ~ '^nascente' THEN E'
• nascente'
              WHEN lower(coalesce(b.sol, '')) ~ '^poente' THEN E'
• poente' ELSE '' END
      || CASE WHEN lower(coalesce(b.mobilia, '')) ~ '^semi' THEN E'
• semi-mobiliado'
              WHEN lower(coalesce(b.mobilia, '')) ~ '^mobiliad' THEN E'
• mobiliado'
              WHEN lower(coalesce(b.mobilia, '')) ~ 'ar.condicionado' THEN E'
• climatizado' ELSE '' END
      || CASE WHEN coalesce(b.valor_venda, 0) > 0
              THEN E'
Venda: R$ ' || replace(to_char(b.valor_venda, 'FM999,999,990'), ',', '.') ELSE '' END
      || CASE WHEN coalesce(b.valor_aluguel, 0) > 0
              THEN E'
Locação: R$ ' || replace(to_char(b.valor_aluguel, 'FM999,999,990'), ',', '.')
                   || CASE WHEN coalesce(b.extras->>'incluso no aluguel', '') ~* 'condom' THEN ' (incluso a tx)' ELSE '' END ELSE '' END
      || E'
Código: ' || b.codigo
    END,
    CASE WHEN coalesce(b.e_parceiro, false) THEN 0 ELSE (SELECT count(*)::int FROM imovel_fotos f WHERE f.codigo = b.codigo) END
  FROM b;
$function$;

CREATE OR REPLACE FUNCTION public.nai_card_do_imovel(p_codigo integer)
 RETURNS TABLE(texto_pronto text, qtd_fotos integer)
 LANGUAGE sql
 STABLE
AS $function$
  -- 191: O CARD DOS GRUPOS (Pedro, 29/09: "o card precisa ser ajustado"). O card
  -- dos grupos e montado pelo publicador lendo o anuncio -- traz lances de
  -- escada, caracteristicas, "aceita financiamento" e a OBS do Tel. O da Nay era
  -- remontado do banco, que nao tem nada disso. Agora a Nay manda o MESMO card,
  -- lido na ficha (ficha_do_anuncio.py), enquanto ele for recente e o preco
  -- bater com o banco. Senao, o card do banco, como sempre.
  SELECT coalesce(
           (SELECT f.card FROM imovel_ficha f JOIN imoveis i ON i.codigo = f.codigo
             WHERE f.codigo = p_codigo AND f.encontrado AND f.erro IS NULL AND f.card IS NOT NULL
               AND f.lido_em > now() - interval '26 hours'
               AND NOT coalesce(i.e_parceiro, false)
               AND coalesce(f.valor_venda, 0) = coalesce(i.valor_venda, 0)
               AND coalesce(f.valor_aluguel, 0) = coalesce(i.valor_aluguel, 0)
               AND f.card ~ ('C[óo]digo:\s*' || p_codigo || '\s*$')),
           b.texto_pronto),
         b.qtd_fotos
    FROM nai_card_do_banco(p_codigo) b;
$function$;

CREATE OR REPLACE FUNCTION public.nai_conferir_resposta(p_turno bigint, p_texto text, p_codigos jsonb, p_escreveu text, p_fotos_site jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  t        nai_turno;
  k        nai_contato;
  v_texto  text := btrim(coalesce(p_texto, ''));
  v_guarda text;
  v_alvo   int;
  v_cods   int[];
  v_sem    int[] := '{}';
  v_gate   boolean := false;
  v_sugerir boolean := false;
  v_base   text;
  v_novo   text;
  v_corretor boolean;
  v_calada boolean;
  c_ok     int;
  c_card   text;
  v_n      int;
  v_ident  boolean := false;
  v_cands  int[];
  v_fichas text;
  v_pg     record;  -- 191
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN jsonb_build_object('acao', 'parou', 'motivo', 'turno_inexistente'); END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  v_corretor := t.papel = 'corretor';
  v_calada := v_texto = '' OR upper(v_texto) ~ '^\W*SIL[EÊ]NCIO\W*$';

  -- 00p ------------------------------------------ PARCERIA (Tel, 28/09/2026)
  -- "Quando o corretor perguntar se aceitamos parceria, ela dizer 'Sim,
  -- aceitamos parceria em todos os nossos imoveis o que precisar pode contar
  -- com a gente'". Vem antes da secretaria de proposito: seja quem for que
  -- respondeu, a frase sai igual. Mensagem so de parceria = so a frase; com
  -- outro assunto junto, a frase vai na frente da resposta dela.
  IF t.papel = 'corretor' AND nai_pergunta_parceria(coalesce(p_escreveu, ''))
     AND v_texto !~* 'aceitamos parceria' THEN
    v_texto := nai_cfg('resposta_parceria', 'Sim, aceitamos parceria em todos os nossos imóveis, o que precisar pode contar com a gente!')
               || CASE WHEN v_calada OR nai_so_parceria(coalesce(p_escreveu, '')) THEN ''
                       ELSE E'\n\n' || v_texto END;
    PERFORM nai_anotar(p_turno, 0, 'parceria', 'mudou', 'resposta fixa de parceria');
    IF v_calada OR nai_so_parceria(coalesce(p_escreveu, '')) THEN
      RETURN jsonb_build_object('acao', 'responder', 'texto', v_texto, 'guarda', 'parceria', 'codigo', NULL);
    END IF;
    v_calada := false;
  END IF;

  -- 00 ------------------------------------------- A SECRETARIA (99)
  -- Turno da secretaria nao passa pelas guardas de locacao: elas cobram card,
  -- código e consulta à base, que é o fluxo da outra. Aqui vale o silêncio
  -- quando não há o que dizer, e nada mais.
  IF t.atendente = 'secretaria' THEN
    IF v_calada THEN
      RETURN jsonb_build_object('acao', 'silencio', 'guarda', 'secretaria_calada');
    END IF;
    RETURN jsonb_build_object('acao', 'responder', 'texto', v_texto,
                              'guarda', 'secretaria', 'codigo', NULL);
  END IF;

  -- 01 -------------------------------------------------- DE QUAL IMÓVEL É
  -- O código do turno (card marcado, card da resposta, o que ele escreveu) e,
  -- faltando esse, o imóvel da CONVERSA. O turno guarda o que achou: é o fio
  -- para a mensagem seguinte ("me manda as fotos dele").
  SELECT CASE WHEN count(DISTINCT x) = 1 THEN min(x)::int END INTO v_alvo
    FROM jsonb_array_elements_text(coalesce(p_codigos, '[]'::jsonb)) x WHERE x ~ '^[0-9]{3,5}$' AND x::int > 0;
  IF v_alvo IS NULL THEN v_alvo := nai_imovel_da_conversa(t.contato_id, p_escreveu); END IF;
  IF v_alvo IS NOT NULL THEN
    UPDATE nai_turno SET codigo = v_alvo WHERE id = p_turno AND codigo IS DISTINCT FROM v_alvo;
  END IF;
  PERFORM nai_anotar(p_turno, 1, 'imovel_da_conversa',
                     CASE WHEN v_alvo IS NULL THEN 'passou' ELSE 'mudou' END,
                     coalesce('imóvel ' || v_alvo, 'nenhum imóvel identificado'));

  -- 02 ------------------------------------------- FOTOS LIDAS NO SITE (camada 2)
  v_n := nai_gravar_fotos_do_site(p_fotos_site);
  PERFORM nai_anotar(p_turno, 2, 'fotos_do_site', CASE WHEN v_n > 0 THEN 'mudou' ELSE 'passou' END,
                     CASE WHEN v_n > 0 THEN v_n || ' fotos gravadas do anúncio' END);

  -- 02a ------------------------- LINK DE CATÁLOGO NÃO DIZ QUAL IMÓVEL É (111)
  -- Sem código na conversa, qualquer imóvel que ela mandasse aqui seria
  -- chute. O Tel recebe o link e responde; ela diz que recebeu, e não cala.
  IF t.papel = 'corretor' AND v_alvo IS NULL
     AND nai_e_link_de_produto(coalesce(p_escreveu, '')) THEN
    v_base := nai_escalar_link_de_catalogo(p_turno, p_escreveu);
    PERFORM nai_anotar(p_turno, 2, 'link_de_catalogo', 'mudou',
                       'link de produto sem código: subiu ao Tel');
    RETURN jsonb_build_object('acao', 'responder', 'texto', v_base,
                              'guarda', 'link_de_catalogo', 'codigo', NULL);
  END IF;

  -- 02b ------------------------------------------ ELA NÃO FAZ CADASTRO (97)
  -- Oferta de imóvel dele é pergunta para o Tel. Tem que ser AQUI, antes de
  -- tudo: o card e as fotos só são enfileirados depois que esta função
  -- devolve 'responder'. O Tel e o Fernando ficam de fora pelo papel.
  IF t.papel IN ('corretor', 'proprietario')
     AND NOT nai_secretaria_ligada()
     AND nai_oferece_imovel(coalesce(p_escreveu, '')) THEN
    PERFORM nai_escalar_cadastro(p_turno, p_escreveu);
    PERFORM nai_anotar(p_turno, 2, 'oferta_de_imovel', 'parou',
                       'ofereceu imóvel: subiu ao Tel e parou o chat');
    RETURN jsonb_build_object('acao', 'parou', 'guarda', 'oferta_de_imovel_foi_ao_tel');
  END IF;

  -- 03 --------------------------------- PERGUNTA SEM RESPOSTA / PROMESSA DE RETORNO
  -- Não existe "vou ver e te aviso": ou responde com a base, ou o Tel responde.
  IF v_corretor AND NOT (coalesce(t.ferramentas, '{}') && ARRAY['escalar', 'visita']::text[])
     AND ((v_calada AND coalesce(p_escreveu, '') ~ '\?') OR v_texto ~* nai_re_promessa()) THEN
    v_base := nai_escalar_calado(p_turno, p_escreveu,
      CASE WHEN v_texto ~* nai_re_promessa() THEN 'prometeu retorno' ELSE 'pergunta sem resposta' END, v_alvo);
    IF v_base IS NULL THEN
      PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'parou', 'subiu ao Tel e parou o chat');
      RETURN jsonb_build_object('acao', 'parou', 'guarda', 'sem_resposta_foi_ao_tel');
    END IF;
    v_texto := v_base; v_calada := false; v_guarda := 'respondido_pela_base';
    PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'mudou', 'a ficha respondeu no lugar');
  ELSIF v_corretor AND 'escalar' = ANY (coalesce(t.ferramentas, '{}')) AND v_texto ~* nai_re_promessa() THEN
    PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'cortou', 'já escalou neste turno: promessa cortada');
    RETURN jsonb_build_object('acao', 'silencio', 'guarda', 'promessa_cortada');
  ELSE
    PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'passou', NULL);
  END IF;

  -- 04 ----------------------------------------------- RESPOSTA SEM CONSULTA
  -- Afirmou sobre imóvel sem ter chamado ferramenta nenhuma.
  IF v_corretor AND '_lidas' = ANY (coalesce(t.ferramentas, '{}'))
     AND coalesce(array_length(array_remove(t.ferramentas, '_lidas'), 1), 0) = 0
     AND NOT v_calada
     AND v_texto !~ '\?\s*\S{0,3}\s*$'
     AND (coalesce(p_escreveu, '') ~ '\?' OR coalesce(p_escreveu, '') ~ '\m\d{3,5}\M')
     AND (coalesce(p_escreveu, '') || ' ' || v_texto) ~* nai_re_assunto_imovel()
     AND v_guarda IS DISTINCT FROM 'respondido_pela_base' THEN
    v_base := nai_escalar_calado(p_turno, p_escreveu, 'respondeu sem consultar a base', v_alvo);
    IF v_base IS NULL THEN
      PERFORM nai_anotar(p_turno, 4, 'resposta_sem_consulta', 'parou', 'afirmou sem ferramenta: subiu ao Tel');
      RETURN jsonb_build_object('acao', 'parou', 'guarda', 'resposta_sem_consulta_foi_ao_tel');
    END IF;
    v_texto := v_base; v_guarda := 'respondido_pela_base';
    PERFORM nai_anotar(p_turno, 4, 'resposta_sem_consulta', 'mudou', 'trocada pela resposta da ficha');
  ELSE
    PERFORM nai_anotar(p_turno, 4, 'resposta_sem_consulta', 'passou', NULL);
  END IF;

  -- 05 ------------------------------------------- O FORMATO É DO TEL, NÃO DO MODELO
  -- 190: a resposta da BUSCA nao vira a ficha de um imovel. Em 29/09 a lista
  -- de locacao virou "Sim! Tem 4 quartos..." do 5748, de venda.
  IF v_corretor AND v_alvo IS NOT NULL AND coalesce(p_escreveu, '') ~ '\?'
     AND v_texto !~* 'c[óo]digo:'
     AND NOT ('buscar_por_perfil' = ANY (coalesce(t.ferramentas, '{}')))
     AND NOT (coalesce(t.ferramentas, '{}') && ARRAY['escalar', 'visita']::text[]) THEN
    v_base := nai_resposta_da_base(v_alvo, p_escreveu);
    IF v_base IS NOT NULL AND v_texto IS DISTINCT FROM v_base THEN
      v_texto := v_base; v_calada := false;
      v_guarda := coalesce(v_guarda || '+', '') || 'formato_da_base';
      PERFORM nai_anotar(p_turno, 5, 'formato_da_base', 'mudou', 'resposta da ficha, no formato dele');
    ELSE
      PERFORM nai_anotar(p_turno, 5, 'formato_da_base', 'passou', NULL);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 5, 'formato_da_base', 'passou', NULL);
  END IF;

  -- 05p ------------------------------ FORMA DE PAGAMENTO SO COM A FICHA (191)
  -- A Nay disse ao Paulo que o Living Comfort (5664) era "somente a vista", e
  -- depois confirmou quando ele repetiu. O anuncio diz que aceita financiamento.
  -- Toda frase dela que afirma forma de pagamento e conferida com a ficha do
  -- imovel de que fala: contradiz -> vira a frase certa; a ficha nao diz -> a
  -- frase sai e, se ele perguntou disso, o Tel e chamado.
  IF v_corretor AND NOT v_calada AND v_texto ~* nai_re_pagamento() THEN
    SELECT * INTO v_pg FROM nai_conferir_pagamento(v_texto, v_alvo);
    IF v_pg.trocas > 0 THEN
      v_texto := v_pg.texto;
      v_guarda := coalesce(v_guarda || '+', '') || 'pagamento_da_ficha';
      PERFORM nai_anotar(p_turno, 5, 'pagamento_da_ficha', 'mudou', 'afirmacao de pagamento corrigida pela ficha');
    END IF;
    IF coalesce(array_length(v_pg.sem_dado, 1), 0) > 0 THEN
      v_texto := v_pg.texto;
      IF nai_assunto_sensivel(coalesce(p_escreveu, '')) IN ('pagamento', 'fgts', 'permuta') OR btrim(v_texto) = '' THEN
        v_base := nai_escalar_calado(p_turno, p_escreveu, 'forma de pagamento que a ficha nao diz',
                                     (SELECT c FROM unnest(v_pg.sem_dado) c WHERE c > 0 LIMIT 1));
        IF v_base IS NULL THEN
          PERFORM nai_anotar(p_turno, 5, 'pagamento_da_ficha', 'parou', 'a ficha nao diz: subiu ao Tel e parou o chat');
          RETURN jsonb_build_object('acao', 'parou', 'guarda', 'pagamento_sem_ficha_foi_ao_tel');
        END IF;
        v_texto := v_base;
      END IF;
      v_guarda := coalesce(v_guarda || '+', '') || 'pagamento_sem_ficha';
      PERFORM nai_anotar(p_turno, 5, 'pagamento_da_ficha', 'mudou', 'afirmacao sem ficha tirada: '
                         || array_to_string(v_pg.sem_dado, ', '));
    END IF;
  END IF;

  -- 06 ------------------------------------------------------------- SILÊNCIO
  IF v_texto = '' OR upper(v_texto) ~ '^\W*SIL[EÊ]NCIO\W*$' THEN
    PERFORM nai_anotar(p_turno, 6, 'silencio', 'parou', 'ela não responde nada, de propósito');
    RETURN jsonb_build_object('acao', 'silencio', 'guarda', v_guarda);
  END IF;
  PERFORM nai_anotar(p_turno, 6, 'silencio', 'passou', NULL);

  -- 07 ---------------------------------------------------- A VOZ DE CADA PAPEL
  IF t.papel IN ('proprietario', 'motoboy') THEN
    v_novo := nai_sem_emoji(v_texto);
    PERFORM nai_anotar(p_turno, 7, 'voz_sem_emoji', CASE WHEN v_novo <> v_texto THEN 'mudou' ELSE 'passou' END,
                       'proprietário e ' || nai_acompanhante() || ': voz da captação');
    v_texto := v_novo;
  ELSE
    PERFORM nai_anotar(p_turno, 7, 'voz_sem_emoji', 'passou', NULL);
  END IF;

  -- 08 ------------------------------------------ SUGERIR VISITA (uma vez por dia)
  IF v_corretor AND v_texto !~ '\?'
     AND (v_guarda LIKE '%respondido_pela_base%' OR v_guarda LIKE '%formato_da_base%' OR v_texto ~* '^\s*sobre isso:'
          OR coalesce(t.ferramentas, '{}') && ARRAY['o_que_sei_do_imovel', 'imovel_por_codigo',
                                                    'disponibilidade_no_condominio', 'listar_no_condominio',
                                                    'resumo_do_condominio']::text[])
     AND NOT (coalesce(t.ferramentas, '{}') && ARRAY['escalar', 'visita']::text[])
     AND v_texto !~* nai_re_sugere_visita()
     AND coalesce((k.visita_sugerida_em AT TIME ZONE 'America/Manaus')::date, date '1900-01-01')
         <> (now() AT TIME ZONE 'America/Manaus')::date
     AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = k.id AND nai_visita_aberta(x.estado)) THEN
    v_sugerir := true;
    PERFORM nai_anotar(p_turno, 8, 'sugerir_visita', 'mudou', 'sai em outra mensagem, depois da resposta');
  ELSE
    PERFORM nai_anotar(p_turno, 8, 'sugerir_visita', 'passou', NULL);
  END IF;

  -- 09 ------------------------------------------ SUGESTÃO REPETIDA NO MESMO DIA
  IF v_corretor AND v_texto ~* nai_re_sugere_visita()
     AND NOT coalesce(nay_pede_visita(coalesce(p_escreveu, '')), false)
     AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = k.id AND x.estado IN ('coletando', 'negociando')) THEN
    IF (k.visita_sugerida_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date THEN
      v_texto := btrim(regexp_replace(v_texto, '(\m(e|se)\s+)?' || nai_re_sugere_visita() || '[^?!\n]*[?!]?', '', 'gi'));
      v_guarda := 'visita_repetida_cortada';
      PERFORM nai_anotar(p_turno, 9, 'sugestao_repetida', 'cortou', 'já sugeriu visita hoje');
      IF v_texto = '' THEN
        RETURN jsonb_build_object('acao', 'silencio', 'guarda', v_guarda);
      END IF;
    ELSE
      UPDATE nai_contato SET visita_sugerida_em = now() WHERE id = k.id;
      PERFORM nai_anotar(p_turno, 9, 'sugestao_repetida', 'passou', 'primeira sugestão do dia, registrada');
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 9, 'sugestao_repetida', 'passou', NULL);
  END IF;

  -- 10 --------------------------------------------- NEGOU IMÓVEL QUE EXISTE
  IF v_corretor AND v_texto ~* nai_re_nega_imovel() THEN
    SELECT i.codigo INTO c_ok
      FROM unnest(coalesce(nay_codigos_citados(coalesce(p_escreveu, '')), '{}'::text[])) x
      JOIN imoveis i ON i.codigo::text = x
     WHERE x ~ '^[0-9]{3,5}$'
       AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     ORDER BY i.codigo LIMIT 1;
    IF c_ok IS NOT NULL THEN
      SELECT texto_pronto INTO c_card FROM nai_card_do_imovel(c_ok);
      IF coalesce(c_card, '') <> '' THEN
        v_texto := c_card;
        v_guarda := coalesce(v_guarda || '+', '') || 'negou_imovel_que_existe';
        PERFORM nai_anotar(p_turno, 10, 'negou_imovel_que_existe', 'mudou', 'negativa trocada pelo card do ' || c_ok);
      END IF;
    ELSE
      PERFORM nai_anotar(p_turno, 10, 'negou_imovel_que_existe', 'passou', 'negou, mas o código não é nosso ou não está no ar');
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 10, 'negou_imovel_que_existe', 'passou', NULL);
  END IF;

  -- 11 -------------------------------------- FRASE DE VISITA SEM A FERRAMENTA
  IF v_corretor AND NOT ('visita' = ANY (coalesce(t.ferramentas, '{}')))
     AND v_texto ~* nai_re_frase_de_visita() THEN
    v_texto := nai_tirar_frase(v_texto, nai_re_frase_de_visita());
    v_guarda := coalesce(v_guarda || '+', '') || 'visita_sem_ferramenta';
    PERFORM nai_avisar_tel(p_turno, NULL,
      'Tel, o corretor ' || coalesce(k.nome_completo, k.nome_whatsapp, k.telefone) ||
      ' (' || nai_fone_fmt(k.telefone) || ') falou de visita e eu não consegui resolver aqui. Ele disse: "' ||
      left(coalesce(p_escreveu, ''), 300) ||
      E'". Não respondi nada e parei de responder esse chat: quem responde é você. Para eu voltar: DEVOLVER ' || nai_fone_fmt(k.telefone) || '.',
      'visita_sem_ferramenta');
    PERFORM nai_parar_chat(k.id, 'visita que eu nao consegui tratar');
    PERFORM nai_anotar(p_turno, 11, 'visita_sem_ferramenta', 'parou', 'falou de visita sem chamar a ferramenta');
    RETURN jsonb_build_object('acao', 'parou', 'guarda', v_guarda);
  END IF;
  PERFORM nai_anotar(p_turno, 11, 'visita_sem_ferramenta', 'passou', NULL);

  -- 12 ------------------------------------------------------ CITOU O TEL
  IF t.papel IN ('corretor', 'proprietario', 'motoboy') AND v_texto ~* '\mtel\M' THEN
    v_texto := nai_tirar_frase(v_texto, '\mtel\M');
    v_guarda := coalesce(v_guarda || '+', '') || 'citou_o_tel_cortado';
    PERFORM nai_anotar(p_turno, 12, 'citou_o_tel', 'cortou', 'quem sobe para o Tel não conta para ninguém');
    IF v_texto = '' THEN
      RETURN jsonb_build_object('acao', 'silencio', 'guarda', v_guarda);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 12, 'citou_o_tel', 'passou', NULL);
  END IF;

  -- 13 --------------------------------------------- UMA PERGUNTA POR MENSAGEM
  IF v_corretor THEN
    v_novo := nai_uma_pergunta_da_sequencia(v_texto);
    IF v_novo IS NOT NULL THEN
      v_texto := v_novo;
      v_guarda := coalesce(v_guarda || '+', '') || 'sequencia_uma_pergunta';
      PERFORM nai_anotar(p_turno, 13, 'uma_pergunta_por_mensagem', 'mudou', 'juntou duas perguntas: saiu só a primeira');
    ELSE
      PERFORM nai_anotar(p_turno, 13, 'uma_pergunta_por_mensagem', 'passou', NULL);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 13, 'uma_pergunta_por_mensagem', 'passou', NULL);
  END IF;

  -- 14 ------------------------------------------------------------- MARKDOWN
  v_novo := nai_limpar_markdown(v_texto);
  PERFORM nai_anotar(p_turno, 14, 'markdown', CASE WHEN v_novo <> v_texto THEN 'mudou' ELSE 'passou' END, NULL);
  v_texto := v_novo;

  -- 14v ------------------------------------------ VISITA QUE NINGUEM PEDIU (141)
  -- Walter, 28/09 09:28: ele perguntou se o Acquarelle estava disponivel e,
  -- num turno so com "Locacao", ela respondeu "A visita do 5712 seria hoje, as
  -- 11h30?" -- sem ferramenta, sem visita nenhuma no banco. Visita com dia ou
  -- hora so sai de ferramenta ou de visita que existe.
  IF v_corretor AND v_texto ~* '\mvisita'
     AND v_texto ~* '(\m\d{1,2}\s*h\M|\m\d{1,2}h\d{2}|\m\d{1,2}:\d{2}|\mhoje\M|\mamanh)'
     AND NOT coalesce(nay_pede_visita(coalesce(p_escreveu, '')), false)
     AND NOT ('visita' = ANY (coalesce(t.ferramentas, '{}')))
     AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = ANY (nai_contato_irmaos(t.contato_id))
                      AND nai_visita_aberta(x.estado)) THEN
    PERFORM nai_anotar(p_turno, 14, 'visita_inventada', 'parou', left(v_texto, 200));
    RETURN jsonb_build_object('acao', 'silencio', 'guarda', 'visita_inventada');
  END IF;

  -- 14i ------------------------------------------ A FICHA DE IDENTIFICACAO (141)
  -- Tel, 28/09: "ela errou na identificacao do imovel, ela perguntou o codigo
  -- para o corretor, a confirmacao deve ser um modelo tambem, manda nome do
  -- imovel, endereco e preco de aluguel ou preco de venda e o codigo no final
  -- #0000". Quando ela pergunta QUAL imovel -- citando codigo, ou pedindo o
  -- codigo a ele -- a pergunta vira a ficha de cada candidato. Sem foto: as
  -- fotos saem quando ele confirmar.
  IF v_corretor AND position('📍' IN v_texto) = 0 AND v_texto ~ '\?' THEN
    IF v_texto ~* ('(\me\s+(esse|este)\M|\mseria\s+(esse|este|o)\M|voc[eê]\s+(quer|fala|diz)[^?]{0,50}\d{3,5}'
                   || '|qual\s+(deles|desses|dos)\M|de\s+qual\s+(im[oó]vel|deles)|mais\s+informa[cç][oõ]es\s+do\s+im[oó]vel)') THEN
      SELECT coalesce(array_agg(DISTINCT x::int), '{}') INTO v_cands
        FROM unnest(coalesce(nay_codigos_citados(v_texto), '{}'::text[])) x
       WHERE x ~ '^[0-9]{3,5}$' AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = x::int);
    END IF;
    -- O QUE ELE CITOU PELO NOME ENTRA JUNTO (Magna, 28/09: "o Rio negro" -> ela
    -- escolheu o Barra do Rio Negro, de venda; era o Conquista Rio Negro de
    -- 1.900). Com os candidatos do nome, a ficha pergunta "qual deles?" em vez
    -- de afirmar o que o modelo chutou. So os que estao no mercado.
    IF v_ident IS NOT TRUE AND (coalesce(array_length(v_cands, 1), 0) > 0 OR v_texto ~* 'c[oó]digo') THEN
      SELECT coalesce(array_agg(DISTINCT c ORDER BY c), '{}') INTO v_cands
        FROM unnest(v_cands || coalesce(nai_imovel_pelo_condominio(coalesce(p_escreveu, ''), k.telefone), '{}'::int[])) c
       WHERE nai_imovel_disponivel(c) AND NOT EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = c AND coalesce(i.e_parceiro, false));
    END IF;
    IF coalesce(array_length(v_cands, 1), 0) BETWEEN 1 AND 5 THEN
      SELECT string_agg(nai_ficha_imovel(c), E'\n\n' ORDER BY c) INTO v_fichas FROM unnest(v_cands) c;
      v_texto := CASE WHEN array_length(v_cands, 1) = 1 THEN 'É este imóvel?' ELSE 'Qual deles?' END
                 || E'\n\n' || v_fichas;
      v_ident := true;
      PERFORM nai_anotar(p_turno, 14, 'ficha_de_identificacao', 'mudou', array_to_string(v_cands, ', '));
    END IF;
  END IF;

  -- 14c ------------------------------------------ ELE CONFIRMOU A VISITA (141)
  -- A camada de baixo do "sim": visita esperando a confirmacao dele, ele
  -- respondeu que sim, e o modelo nao chamou pedir_visita. O banco confirma.
  IF v_corretor AND nai_e_sim_curto(coalesce(p_escreveu, ''))
     AND NOT ('visita' = ANY (coalesce(t.ferramentas, '{}')))
     AND EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = ANY (nai_contato_irmaos(t.contato_id))
                  AND x.estado = 'confirmando') THEN
    PERFORM nai_visita_corretor_confirmou(x.id, p_turno)
       FROM nai_visita x WHERE x.corretor_id = ANY (nai_contato_irmaos(t.contato_id)) AND x.estado = 'confirmando';
    PERFORM nai_anotar(p_turno, 14, 'visita_confirmada_pelo_corretor', 'mudou', 'o banco confirmou');
    RETURN jsonb_build_object('acao', 'responder', 'guarda', 'visita_confirmada_pelo_corretor', 'codigo', NULL,
                              'texto', 'Certo! Vou ver esse horário com o proprietário e já te retorno.');
  END IF;

  -- 15 ------------------------------------------- DE QUAIS IMÓVEIS SÃO AS FOTOS
  SELECT coalesce(array_agg(DISTINCT x::int), '{}') INTO v_cods
    FROM jsonb_array_elements_text(coalesce(p_codigos, '[]'::jsonb)) x
   WHERE x ~ '^[0-9]{3,5}$' AND x::int > 0;
  IF t.papel IN ('corretor', 'tel') THEN
    -- AS FOTOS VAO SEMPRE (Tel, 16/09): falou de imovel, recebe informacao e
    -- foto na mesma resposta. Antes era preciso pedir "foto" com todas as
    -- letras, e quem escrevia "me encaminha o 5717" recebia so o card.
    v_gate := coalesce(nai_deve_mandar_fotos(t.contato_id, k.telefone, coalesce(p_escreveu, '')), false);
  END IF;
  -- 190: turno da BUSCA sem card na resposta (pergunta do filtro, lista) nao
  -- manda foto do "imovel da conversa": as fotos saem quando ele escolher.
  IF v_gate AND coalesce(array_length(v_cods, 1), 0) = 0
     AND NOT ('buscar_por_perfil' = ANY (coalesce(t.ferramentas, '{}'))) THEN
    v_cods := array_remove(ARRAY[coalesce(v_alvo, nai_imovel_da_conversa(t.contato_id, p_escreveu))], NULL);
  END IF;
  -- SEM IMOVEL NAO HA FOTO. Com o portao sempre aberto, ele continuava "true"
  -- mesmo quando nao se sabe de qual imovel se fala -- e os passos seguintes
  -- tratavam a resposta como se fotos fossem sair. Medido: seis testes de
  -- formato e de sugestao de visita cairam por isso.
  IF v_gate AND coalesce(array_length(v_cods, 1), 0) = 0 THEN
    v_gate := false;
  END IF;

  -- IMOVEL INDISPONIVEL NAO LEVA FOTO (138): a resposta de situacao lista os
  -- disponiveis do mesmo condominio e pergunta qual interessa. As fotos saem
  -- quando ele escolher -- as do indisponivel, nunca (parede no gatilho).
  IF v_gate AND v_texto ~ '^Hmmm, vi aqui que o' THEN
    v_gate := false;
  END IF;
  -- 141: a ficha de identificacao espera ele confirmar; pedido de visita nao
  -- leva card nem foto na hora ("primeiro confirma se sabe qual e o imovel").
  IF v_gate AND (v_ident OR coalesce(nay_pede_visita(coalesce(p_escreveu, '')), false)) THEN
    v_gate := false;
  END IF;

  -- NAO REPETE (Tel, 16/09): "o Tel ja tinha pedido manualmente para ela mandar
  -- as fotos do arezzo, mas ela foi la e mandou novamente". O imovel cujas
  -- fotos ja sairam para esta pessoa hoje sai da lista -- as informacoes
  -- continuam indo, so as fotos e que nao se repetem.
  -- ...A NAO SER QUE ELE PECA (Tel, 22/09: "manda de novo conforme
  -- solicitado"). A trava vale para foto que ele nao pediu.
  IF v_gate AND coalesce(array_length(v_cods, 1), 0) >= 1
     AND NOT nai_pede_foto(coalesce(p_escreveu, '')) THEN
    SELECT coalesce(array_agg(c), '{}') INTO v_cods
      FROM unnest(v_cods) c
     WHERE NOT nai_fotos_ja_mandadas(t.contato_id, c, 24);
    IF coalesce(array_length(v_cods, 1), 0) = 0 THEN
      v_gate := false;
    END IF;
  END IF;

  PERFORM nai_anotar(p_turno, 15, 'portao_de_fotos', CASE WHEN v_gate THEN 'mudou' ELSE 'passou' END,
                     CASE WHEN v_gate THEN 'ele pediu foto; imóveis: ' || coalesce(array_to_string(v_cods, ', '), 'nenhum')
                          ELSE 'ele não pediu foto' END);

  -- 16 ------------------------------- NEGOU FOTO QUE EXISTE / PROMETEU A QUE NÃO
  IF v_gate AND v_texto ~* nai_re_nega_foto() AND coalesce(array_length(v_cods, 1), 0) >= 1 THEN
    SELECT count(*) INTO v_n FROM imovel_fotos WHERE codigo = v_cods[1];
    IF v_n > 0 THEN
      v_texto := regexp_replace(v_texto, '[^.?!\n]*' || nai_re_nega_foto() || '[^.?!\n]*[.?!]?', 'segue as fotos', 'i');
      v_guarda := 'negacao_corrigida';
      PERFORM nai_anotar(p_turno, 16, 'negou_foto_que_existe', 'mudou', 'a foto existe: negativa trocada');
    END IF;
  END IF;
  IF v_gate THEN
    SELECT coalesce(array_agg(c), '{}') INTO v_sem FROM unnest(v_cods) c
     WHERE NOT EXISTS (SELECT 1 FROM imovel_fotos fx WHERE fx.codigo = c);
    IF coalesce(array_length(v_sem, 1), 0) >= 1 THEN
      -- 14/09: antes esta conferência TROCAVA a frase por "as fotos desse eu vou
      -- confirmar com o Tel e já te mando" -- promessa de retorno, que o fluxo
      -- v17 proíbe ("não existe vou ver e te aviso"). Agora a frase de foto
      -- (promessa ou negativa) sai fora e o Tel é avisado; o corretor não recebe
      -- promessa nenhuma.
      v_texto := nai_tirar_frase(v_texto, nai_re_promete_foto() || '|' || nai_re_nega_foto());
      PERFORM nai_avisar_tel(p_turno, NULL,
        'Tel, o corretor ' || coalesce(k.nome_whatsapp, k.telefone) || ' pediu fotos do ' ||
        array_to_string(v_sem, ', ') || ' e não achei foto nem no banco nem no anúncio do site. Pode me mandar?',
        'foto_inexistente');
      v_guarda := coalesce(v_guarda || '+', '') || 'promessa_sem_foto';
      PERFORM nai_anotar(p_turno, 17, 'foto_que_nao_existe', 'mudou', 'imóvel sem foto: o Tel foi avisado');
    ELSE
      PERFORM nai_anotar(p_turno, 17, 'foto_que_nao_existe', 'passou', NULL);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 17, 'foto_que_nao_existe', 'passou', NULL);
  END IF;

  RETURN jsonb_build_object(
    'acao', 'responder',
    'texto', v_texto,
    'guarda', v_guarda,
    'alvo', v_alvo,
    'cods', to_jsonb(v_cods),
    'gate', v_gate,
    'sugerir', v_sugerir);
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_rodar_casos()
 RETURNS TABLE(passou boolean, regra text, frase text, esperado text, deu text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE c record; v text;
BEGIN
  FOR c IN SELECT * FROM nai_caso WHERE ativo ORDER BY id LOOP
    v := CASE c.pergunta
      WHEN 'tipo'       THEN coalesce(nai_tipo_pedido(c.frase), '-')
      WHEN 'tipo_canon' THEN coalesce(nai_tipo_canonico(c.frase), '-')
      WHEN 'negocio'    THEN coalesce(nay_negocio_pedido(c.frase), '-')
      WHEN 'cortesia'   THEN nai_e_so_cortesia(c.frase)::text
      WHEN 'oferta'     THEN nai_oferece_imovel(c.frase)::text
      WHEN 'anuncio'    THEN nai_e_anuncio_dele(c.frase)::text
      WHEN 'catalogo'   THEN nai_pergunta_de_catalogo(c.frase)::text
      WHEN 'link'       THEN nai_e_link_de_produto(c.frase)::text
      WHEN 'pede_lista' THEN nai_pede_os_valores(c.frase)::text
      WHEN 'sem_bairro' THEN nai_sem_preferencia_de_bairro(c.frase)::text
      WHEN 'de_imovel'  THEN nai_e_assunto_de_locacao(c.frase)::text
      WHEN 'imoveis'    THEN nai_imoveis_pedidos(c.frase, '')::text
      WHEN 'passe'      THEN nai_passe_do_citado(nai_imoveis_pedidos(c.frase, ''))::text
      WHEN 'texto_limpo' THEN nai_texto_sem_os_barrados(c.frase)
      WHEN 'nomes'      THEN nai_corrigir_nomes(c.frase)
      WHEN 'valor'      THEN coalesce(nay_maior_valor(c.frase)::text, '-')
      WHEN 'pelo_nome'  THEN nai_imovel_pelo_condominio(c.frase, '')::text  -- 190
      WHEN 'afirma_pagamento' THEN coalesce(nai_afirmacao_de_pagamento(c.frase), '-')  -- 191
      WHEN 'assunto_sensivel' THEN coalesce(nai_assunto_sensivel(c.frase), '-')  -- 191
      WHEN 'negocio_valor' THEN coalesce(nai_negocio_pelo_valor(c.frase), '-')  -- 190
      WHEN 'tipo_conversa'    THEN coalesce(nai_tipo_das_falas(string_to_array(c.frase, ' || ')), '-')
      WHEN 'negocio_conversa' THEN coalesce(nai_negocio_das_falas(string_to_array(c.frase, ' || ')), '-')
      ELSE '(pergunta desconhecida: ' || c.pergunta || ')'
    END;
    passou := (v = c.esperado);
    regra := c.regra; frase := c.frase; esperado := c.esperado; deu := v;
    RETURN NEXT;
  END LOOP;
END;
$function$;

INSERT INTO nai_caso (quando, quem, frase, pergunta, esperado, regra, ativo) VALUES
 ('2026-09-29', 'Paulo 29/09', 'Já o Living Comfort 5664 é somente à vista.', 'afirma_pagamento', 'so_a_vista', 'afirmar "somente à vista" é conferido com a ficha', true),
 ('2026-09-29', 'Paulo 29/09', 'Certo, Paulo! O Living Comfort é somente à vista mesmo.', 'afirma_pagamento', 'so_a_vista', 'confirmar o erro do corretor também é afirmar', true),
 ('2026-09-29', 'Paulo 29/09', 'A casa 1360 aceita pagamento à vista ou financiado.', 'afirma_pagamento', 'financia', 'aceita financiamento é conferido com a ficha', true),
 ('2026-09-29', 'regra 191', 'Esse não aceita financiamento.', 'afirma_pagamento', 'so_a_vista', 'negar financiamento é afirmar à vista', true),
 ('2026-09-29', 'regra 191', 'Aceita financiamento?', 'afirma_pagamento', '-', 'pergunta não afirma nada', true),
 ('2026-09-29', 'regra 191', 'Aceita FGTS na entrada?', 'assunto_sensivel', 'fgts', 'FGTS só com a ficha ou o Tel', true),
 ('2026-09-29', 'regra 191', 'Pode ser financiado?', 'assunto_sensivel', 'pagamento', 'financiamento só com a ficha ou o Tel', true),
 ('2026-09-29', 'regra 191', 'O proprietário aceita um carro como parte?', 'assunto_sensivel', 'permuta', 'permuta só com a ficha ou o Tel', true),
 ('2026-09-29', 'regra 191', 'O condomínio tem piscina?', 'assunto_sensivel', '-', 'lazer não é assunto sensível: a ficha responde', true);

COMMIT;

