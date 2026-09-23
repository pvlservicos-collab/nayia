-- =====================================================================
-- NAI -- 106: o filtro de palavras (Tel, 23/09/2026)
--
-- Ele: "veja as palavras semelhantes dos bairros e condominios que podem ser
-- o que o cara esta falando, na transcricao vai vir escrito errado igual
-- aquarelli e aquareli, bom pedro e dom pedro. Ela precisa entender isso, que
-- e a palavra, se ela estiver escrita mais ou menos certo, acima de 70% da
-- palavra certa ela conserta a palavra antes ate de enviar para a Nay, algo
-- assim um filtro de palavras".
--
-- O QUE FAZ: pega o texto (vindo de audio ou digitado), varre em janelas de
-- 3, 2 e 1 palavras e troca pelo NOME CERTO quando a semelhanca passa de 70%.
--
--   "bom pedro"    -> Dom Pedro          (bairro)
--   "aquarelli"    -> Acquarelle         (condominio)
--   "ponta negrra" -> Ponta Negra        (bairro)
--   "tarumaassu"   -> Tarumã-Açu         (bairro)
--
-- O VOCABULARIO SAI DO CATALOGO: os bairros com imovel no mercado e os
-- nucleos dos condominios. Ninguem mantem lista a mao -- entrou condominio
-- novo, ele ja entra no filtro.
--
-- AS TRAVAS (sem elas, um filtro assim estraga mais do que conserta):
--   - palavra com menos de 5 letras nao e corrigida ("casa", "pet", "2k");
--   - palavra que ja esta certa nao e tocada;
--   - o que e TIPO de imovel fica fora do vocabulario: existe condominio
--     cadastrado com o nome "Casa", "Apartamento" e "Predio", e sem esta
--     trava "casa" viraria nome proprio;
--   - palavra comum do portugues nao e candidata (a lista esta em
--     `nai_palavra_comum`), senao "procurando" vira "Coroado";
--   - o piso fica em `nai_config.piso_correcao_nome` (0.70), como ele pediu.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO nai_config (chave, valor) VALUES ('piso_correcao_nome', '0.70')
ON CONFLICT (chave) DO NOTHING;

-- 1 ----------------------------------------------- O QUE NUNCA E NOME PROPRIO
CREATE OR REPLACE FUNCTION public.nai_palavra_comum(p_palavra text)
 RETURNS boolean LANGUAGE sql IMMUTABLE
AS $function$
  SELECT lower(unaccent(coalesce(p_palavra, ''))) = ANY (ARRAY[
    'casa','casas','apartamento','apartamentos','apto','aptos','predio','sala','salas',
    'lote','lotes','terreno','cobertura','flat','loja','galpao','chacara','imovel','imoveis',
    'aluguel','alugar','locacao','venda','vender','comprar','cliente','clientes','corretor',
    'quarto','quartos','suite','suites','vaga','vagas','banheiro','banheiros','mobiliado',
    'semimobiliado','condominio','bairro','valor','valores','preco','precos','visita','visitar',
    'disponivel','procurando','procura','preciso','precisa','obrigado','obrigada','bom','boa',
    'dia','tarde','noite','tudo','bem','sim','nao','esse','essa','isso','aqui','ali','para',
    'pela','pelo','com','sem','mais','menos','muito','pouco','tambem','ainda','agora','depois',
    'manaus','amazonas','reais','mil','milhao','area','areas','metros','andar','novo','nova',
    'velho','antigo','grande','pequeno','melhor','pior','certo','errado','poder','pode','quer',
    'quero','tenho','tem','vou','vai','esta','estao','fica','ficam','manda','mandar','envia',
    'enviar','fotos','foto','video','audio','arquivo','whatsapp','grupo','link','site'
  ]);
$function$;

-- 2 ------------------------------------------- O VOCABULARIO DA NOSSA CASA
CREATE OR REPLACE VIEW vw_vocabulario_nomes AS
  -- os bairros com imovel no mercado
  SELECT DISTINCT btrim(i.bairro) AS nome, 'bairro'::text AS especie
    FROM imoveis i
   WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     AND btrim(coalesce(i.bairro, '')) <> ''
     AND length(btrim(i.bairro)) >= 5
  UNION
  -- e o nucleo dos condominios (sem "Condominio/Residencial/Edificio")
  SELECT DISTINCT v.nucleo, 'condominio'::text
    FROM vw_condominio_som v
   WHERE length(coalesce(v.nucleo, '')) >= 5
     AND NOT nai_palavra_comum(v.nucleo);

-- 3 ------------------------------------------------------- O FILTRO
CREATE OR REPLACE FUNCTION public.nai_corrigir_nomes(p_texto text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_palavras text[];
  v_saida    text[] := '{}';
  v_piso     real := coalesce(nullif(nai_cfg('piso_correcao_nome', '0.70'), ''), '0.70')::real;
  i          int := 1;
  n          int;
  j          int;
  v_janela   text;
  v_limpo    text;
  v_certo    text;
  v_forca    real;
  v_achou    boolean;
BEGIN
  IF btrim(coalesce(p_texto, '')) = '' THEN RETURN p_texto; END IF;
  v_palavras := regexp_split_to_array(p_texto, '\s+');
  n := coalesce(array_length(v_palavras, 1), 0);

  WHILE i <= n LOOP
    v_achou := false;
    -- JANELA GRANDE PRIMEIRO: "bom pedro" antes de "bom" e "pedro" soltos.
    FOR j IN REVERSE least(3, n - i + 1) .. 1 LOOP
      v_janela := array_to_string(v_palavras[i : i + j - 1], ' ');
      v_limpo  := btrim(regexp_replace(v_janela, '[^[:alnum:] ]', '', 'g'));
      -- so o miolo de letras conta: pontuacao nao entra na comparacao
      CONTINUE WHEN length(regexp_replace(lower(unaccent(v_janela)), '[^a-z0-9]', '', 'g')) < 5;
      CONTINUE WHEN j = 1 AND nai_palavra_comum(regexp_replace(v_janela, '[^[:alnum:]]', '', 'g'));

      -- A REGUA E DE LETRAS, nao de trigramas (Tel: "acima de 70% da palavra
      -- certa"). Medido: "bom pedro" x "Dom Pedro" da 0,54 de trigrama e
      -- 0,89 de letras; "aquarelli" x "Acquarelle" da 0,80 de letras. Com
      -- trigrama, os dois casos que ele apontou passariam batido.
      -- O trigrama fica junto, pelo maior dos dois: ele ainda ajuda quando a
      -- pessoa troca a ORDEM das palavras.
      SELECT x.nome, x.forca INTO v_certo, v_forca FROM (
        SELECT v.nome,
               greatest(
                 similarity(lower(unaccent(v.nome)), lower(unaccent(v_limpo))),
                 1.0 - levenshtein(lower(unaccent(v.nome)), lower(unaccent(v_limpo)))::real
                       / greatest(length(v.nome), length(v_limpo), 1)
               ) AS forca
          FROM vw_vocabulario_nomes v
         -- A JANELA TEM QUE TER O MESMO TANTO DE PALAVRAS DO NOME. Sem isto,
         -- "em ponta negrra" (3) casava com "Ponta Negra" (2) e o "em" era
         -- engolido: saia "quero Ponta Negra".
         WHERE array_length(regexp_split_to_array(btrim(v.nome), '\s+'), 1) = j
         ORDER BY 2 DESC LIMIT 1) x;

      IF v_certo IS NOT NULL AND v_forca >= v_piso THEN
        -- ja esta certo: nao mexe
        IF lower(unaccent(v_limpo)) = lower(unaccent(v_certo)) THEN
          v_saida := v_saida || v_palavras[i : i + j - 1];
        ELSE
          -- a pontuacao do fim da janela volta junto ("dom pedro," continua com a virgula)
          v_saida := v_saida || (v_certo || coalesce((regexp_match(v_palavras[i + j - 1], '([^[:alnum:]]+)$'))[1], ''));
        END IF;
        i := i + j;
        v_achou := true;
        EXIT;
      END IF;
    END LOOP;

    IF NOT v_achou THEN
      v_saida := v_saida || v_palavras[i];
      i := i + 1;
    END IF;
  END LOOP;

  RETURN array_to_string(v_saida, ' ');
END;
$function$;

COMMIT;

-- O QUE TEM QUE CONSERTAR                                e o que NAO pode tocar.
SELECT t AS veio_assim, nai_corrigir_nomes(t) AS ela_le_assim
  FROM unnest(ARRAY[
    'Alvorada, Bom Pedro, né? Essas mediações de casa para aluguel',
    'o aquarelli de 3 quartos ainda ta disponivel?',
    'tem no aquareli?',
    'quero em ponta negrra',
    'casa no tarumaassu',
    'me manda as fotos do 5611',
    'meu cliente quer 2 quartos até 3 mil',
    'boa tarde, tudo bem? preciso de uma casa mobiliada',
    'o contrato foi assinado ontem'
  ]) t;
