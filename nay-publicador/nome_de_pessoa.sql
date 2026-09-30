-- O primeiro nome da PESSOA, tirado do nome de WhatsApp.
--
-- O CASO (01/09): o corretor aparece como "OPEN SERVIÇOS" e a Nay
-- cumprimentou "Olá, OPEN SERVIÇOS!". O Tel: "esse é um nome de empresa,
-- ela tem que perguntar o nome da pessoa".
--
-- POR QUE NÃO BASTA A REGRA NO PROMPT: o que o modelo vê é o `senderName`
-- cru da Z-API, e a regra é reavaliada a cada mensagem, com o nome errado
-- na frente dele. Aqui o dado chega já resolvido: ou é nome de gente, ou é
-- NULL -- e NULL já faz o prompt dizer "nao sei o nome dele", que é o
-- caminho que manda ela perguntar.
--
-- O CRITÉRIO É ESTREITO DE PROPÓSITO. Perguntar o nome de quem já tem nome
-- é chato e acontece com muito mais gente do que o contrário: metade da
-- carteira escreve "Fulano Corretor de Imóveis". Então só vira NULL quem
-- não sobra NADA depois de tirar profissão e CRECI, ou quem tem marca
-- explícita de empresa (LTDA, ME, EIRELI, IMOBILIÁRIA, CONSTRUTORA...).
-- "Ana Imóveis" continua sendo Ana.
--
--   docker cp nome_de_pessoa.sql nay-postgres:/tmp/np.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/np.sql

CREATE OR REPLACE FUNCTION nay_nome_de_pessoa(p_nome text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $fn$
DECLARE
  v_t text := btrim(coalesce(p_nome,''));
  v_c text;
BEGIN
  IF v_t = '' THEN RETURN NULL; END IF;

  -- Só o pedaço antes do separador: "Marcos | Corretor", "Ana - CRECI 123".
  v_t := btrim(split_part(split_part(split_part(v_t,'|',1),'/',1),' - ',1));

  -- Fora emoji, símbolo e pontuação. `[[:alpha:]]` respeita acento.
  v_c := btrim(regexp_replace(v_t, '[^[:alpha:][:space:]'']', ' ', 'g'));
  v_c := btrim(regexp_replace(v_c, '\s+', ' ', 'g'));
  IF v_c = '' THEN RETURN NULL; END IF;

  -- Marca explícita de empresa: aí não há nome de pessoa a extrair, mesmo
  -- que sobre palavra. "OPEN SERVIÇOS", "Silva Imobiliária Ltda".
  IF v_c ~* ('\m(ltda|eireli|epp|mei|imobiliaria|imobiliarias|construtora|'
             || 'incorporadora|empreendimentos|servicos|serviços|solucoes|'
             || 'soluções|assessoria|consultoria|administradora|adm|'
             || 'negocios|negócios|group|grupo|company|corp)\M') THEN
    RETURN NULL;
  END IF;

  -- Profissão e credencial saem; o que sobra é candidato a nome.
  v_c := btrim(regexp_replace(v_c,
           '\m(corretor|corretora|corretores|creci|imovel|imoveis|imóvel|imóveis|'
           || 'consultor|consultora|representante|vendas|vendedor|vendedora|'
           || 'de|da|do|dos|das|e)\M', ' ', 'gi'));
  v_c := btrim(regexp_replace(v_c, '\s+', ' ', 'g'));
  IF v_c = '' THEN RETURN NULL; END IF;

  -- Inicial não é nome: "J. Bosco Melo" é o Bosco, não o "J". Tira as
  -- iniciais da frente até sobrar uma palavra de verdade.
  WHILE v_c <> '' AND length(split_part(v_c,' ',1)) < 2 LOOP
    v_c := btrim(substr(v_c, position(' ' in v_c || ' ')));
  END LOOP;
  IF v_c = '' THEN RETURN NULL; END IF;

  RETURN initcap(split_part(v_c,' ',1));
END;
$fn$;
