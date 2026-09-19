-- Tratamento (Sr. / Sra.) deduzido do nome do proprietario.
--
-- Por que no BANCO e nao no n8n: o Tel pediu um campo pronto em todos os
-- contatos, calculado antes, sem depender do fluxo. Assim da para CONFERIR
-- a lista inteira antes de mandar mensagem -- e errar o tratamento de uma
-- mulher e o tipo de erro que mata a conversa na primeira linha.
--
-- REGRA DE OURO: na duvida devolve NULL, nao chuta. NULL faz a mensagem
-- sair sem vocativo de tratamento ("Ola Maria, bom dia!") em vez de sair
-- com o tratamento errado ("Ola Sr. Maria"). O CRM mostra os NULL para o
-- Tel resolver na mao.

BEGIN;

-- ---------------------------------------------------------------------
-- Tira acento sem depender da extensao unaccent (que nao esta instalada).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nay_sem_acento(txt text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT translate(
    lower(coalesce(txt, '')),
    'áàâãäéèêëíìîïóòôõöúùûüçñýÿ',
    'aaaaaeeeeiiiiooooouuuucny'
  );
$$;

-- ---------------------------------------------------------------------
-- Primeiro nome limpo.
--
-- A base tem lixo real que precisa sair antes: nome comecando com "Sr."
-- ou "Sra" (24 casos), parenteses "(Taise)", hifen solto "Sandra-",
-- caractere invisivel no comeco, e entradas que nao sao nome nenhum
-- ("Corretora", "ADM", "Cc496").
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nay_primeiro_nome(nome text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT NULLIF(btrim(
    -- 4. so letras
    regexp_replace(
      -- 3. primeiro token
      split_part(
        btrim(
          -- 2. tira o tratamento que ja vem embutido no nome
          regexp_replace(
            -- 1. tira invisiveis e pontuacao de borda
            regexp_replace(coalesce(nome, ''), '[​-‏‪-‮﻿]', '', 'g'),
            '^\s*(sr\.?|sra\.?|dr\.?|dra\.?|dona|exmo\.?|exma\.?)\s+', '', 'i')
        ), ' ', 1),
      '[^A-Za-zÀ-ÿ]', '', 'g')
  ), '');
$$;

-- ---------------------------------------------------------------------
-- O tratamento.
--
-- Ordem de decisao, da evidencia mais forte para a mais fraca:
--   1. o proprio cadastro ja diz ("Sr. Fulano", "Sra. Fulana", "Dona X")
--   2. lixo conhecido -> NULL (nao e nome de gente)
--   3. lista de excecao -> nomes que as regras de sufixo erram
--   4. regras de sufixo do portugues
--   5. nada disso -> NULL
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nay_tratamento_por_nome(nome text) RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  cru       text := coalesce(nome, '');
  primeiro  text;
  n         text;
  -- Nao sao nomes de pessoa: cargo, empresa, sobrenome solto, codigo.
  -- Sobrenome sozinho nao diz genero -- "Souza" pode ser qualquer um.
  lixo text[] := ARRAY[
    'adm','administracao','amazonas','bmb','bros','ccx','columbia',
    'corretor','corretora','costa','froes','guimaraes','imob','ingled',
    'lima','lobo','loureiro','marques','messa','neto','pacheco','rossetti',
    'santos','souza','teles','xavier','salazarbroker','tel','vir','dona',
    'uchoa','carolinemarlon'
  ];
  -- Femininos que nenhuma regra de sufixo pegaria.
  -- Os terminados em -n (Vivian, Andrielen, Evelyn) sao o grupo perigoso:
  -- a regra manda -n para masculino por causa de Anderson/Wilson/Robson.
  fem text[] := ARRAY[
    'carmem','elizabeth','ellen','elen','hellen','helen','maureen',
    'evelyn','vivian','andrielen','karen','sharon','miriam','suelem','viviam',
    'ruth','hildeth','ingrid','iris','lurdes','raquel',
    'lucy','meiry','hanny','mel','mari','rosi','josi','naty','karol','carol',
    'socorro','luz','ines','ester','esther','isabel','erli',
    'taise','marides','misuzi','sully','loyzi','lais','iraci',
    'edlainy','adrya','nilce','stella','flor','fatima','kirley','beatris',
    'suzy','suzie','anahie','judith','nair','madalena'
  ];
  -- Masculinos que as regras de sufixo NAO pegariam. A parte critica sao
  -- os terminados em -e, que a regra nova manda para feminino.
  masc text[] := ARRAY[
    -- terminados em -e (lista fechada que a regra -e precisa excluir)
    'andre','alexandre','felipe','henrique','jorge','jose','jesse','cosme',
    'guilherme','vicente','clemente','dante','jaime','jayme','aristides',
    -- terminados em -a
    'osma','arimateia','juca','noa','luca',
    -- terminados em -y / -i / -u / -m / -ck / -t e outros irregulares
    'moacy','ary','levy','sammy','kennedy','dargley','mayko','tony','jony',
    'ney','sidney','fillipy','thyago','ray','erick','mozart','roney',
    'tadeu','william','joaquim','max','alex','denys','frank','robert',
    'richard','david','davi','enzo','juan','raul','salim','jamil','elias',
    'isaac','ivan','arlan','darlan','leonan','orlean','kairo','higor','hugo',
    'thomas','sadoch','rusbeval','telmario','wamberto','dunhellington',
    'anchinzio','astrogildo','damasio','euvaldo','ribamar','nonato','junior',
    'michel','gabriel','daniel','manoel','manuel','natanael','rafael',
    'raphael','leonel','jardel','israel','ismael','joel','emanuel','miguel',
    'samuel','nel','hermes','pericles','moises','marcos','lucas','matias'
  ];
BEGIN
  -- 1. Nao e pessoa fisica: imobiliaria, construtora, empresa. Estes nao
  -- levam Sr./Sra. nenhum, e chutar aqui produz "Sra. Uchoa Imoveis".
  --
  -- CUIDADO: "corretor"/"parceiro" NAO entram nesta lista. Medido na base:
  -- 170 cadastros trazem "(Parceira)" ou "(Corretor Parceiro)" como
  -- ANOTACAO ao lado de um nome de gente de verdade -- "Zilene (Parceira)",
  -- "Marlene Moreira (Parceira)", "Jane Farias (Parceira)". Barrar por essa
  -- palavra jogava 170 pessoas para "nao sei" sem motivo.
  IF cru ~* '(im[oó]veis|imobili[aá]ri|ltda|eireli|empreendiment|construtor)'
    THEN RETURN NULL; END IF;

  -- 2. O cadastro ja declara o tratamento. E a evidencia mais forte que
  -- existe: alguem digitou isso olhando para a pessoa.
  IF cru ~* '^\s*(sra\.?|dona|exma\.?|dra\.?)\s+' THEN RETURN 'Sra.'; END IF;
  IF cru ~* '^\s*(sr\.?|exmo\.?|dr\.?)\s+'        THEN RETURN 'Sr.';  END IF;

  primeiro := nay_primeiro_nome(cru);
  IF primeiro IS NULL OR length(primeiro) < 3 THEN RETURN NULL; END IF;

  n := nay_sem_acento(primeiro);

  IF n = ANY(lixo) THEN RETURN NULL;   END IF;
  IF n = ANY(masc) THEN RETURN 'Sr.';  END IF;   -- excecao vem antes da regra
  IF n = ANY(fem)  THEN RETURN 'Sra.'; END IF;

  -- 3. Regras de sufixo, da mais especifica para a mais geral.
  IF n ~ '(ah|th)$'   THEN RETURN 'Sra.'; END IF;  -- Sarah, Deborah, Ruth
  IF n ~ 'im$'        THEN RETURN 'Sr.';  END IF;  -- Joaquim, Serafim
  IF n ~ 'a$'         THEN RETURN 'Sra.'; END IF;  -- Ana, Maria, Juliana
  IF n ~ 'e$'         THEN RETURN 'Sra.'; END IF;  -- Adriane, Liliane, Daniele
  IF n ~ 'o$'         THEN RETURN 'Sr.';  END IF;  -- Paulo, Ricardo
  IF n ~ 'u$'         THEN RETURN 'Sr.';  END IF;  -- Tadeu
  IF n ~ '(s|z|l|r)$' THEN RETURN 'Sr.';  END IF;  -- Marcos, Luiz, Gabriel, Valdir
  IF n ~ 'n$'         THEN RETURN 'Sr.';  END IF;  -- Anderson, Wilson, Robson

  -- 4. Ultimo recurso: a propria anotacao do cadastro tem genero.
  -- "(Parceira)" / "(Corretora)" so se escreve de mulher.
  IF cru ~* '\((parceira|corretora)\)' THEN RETURN 'Sra.'; END IF;
  IF cru ~* '\((parceiro|corretor)\)'  THEN RETURN 'Sr.';  END IF;

  -- 5. Terminacao -i, -y, -m e o resto sao mistas demais para chutar.
  RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------
-- Coluna para marcar o que o Tel conferiu ou corrigiu na mao.
-- Sem ela, um recalculo em massa apagaria a correcao humana.
-- ---------------------------------------------------------------------
ALTER TABLE captacao_leads
  ADD COLUMN IF NOT EXISTS tratamento_manual boolean NOT NULL DEFAULT false;

-- O CHECK garante que so entra o que a mensagem sabe usar.
ALTER TABLE captacao_leads DROP CONSTRAINT IF EXISTS captacao_lead_tratamento_ok;
ALTER TABLE captacao_leads ADD CONSTRAINT captacao_lead_tratamento_ok
  CHECK (tratamento IS NULL OR tratamento IN ('Sr.', 'Sra.'));

-- O default 'Sr.' da tabela era um chute embutido: todo lead nascia homem.
-- Sem default, quem nao souber nasce NULL e aparece para conferencia.
ALTER TABLE captacao_leads ALTER COLUMN tratamento DROP DEFAULT;

COMMIT;
