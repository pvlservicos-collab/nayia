-- =====================================================================
-- NAI -- 57: "Corretor" no nome diz o genero (Tel, 16/09/2026)
--
-- Ele: "ela mandou Sra. Fiuza sendo que e um corretor".
--
-- O cadastro dele e "Fiuza - Corretor CRECI 8383". A palavra "Corretor" estava
-- escrita ali, mas a regra de genero so a enxergava dentro de parenteses --
-- "(Corretor Parceiro)", que e como 170 cadastros antigos foram escritos. Sem
-- ela, sobrou o sufixo: "Fiuza" termina em -a, e a regra manda tudo o que
-- termina em -a para o feminino.
--
-- O QUE MUDA: a anotacao de papel passa a valer com ou sem parenteses, e sobe
-- para o topo da funcao -- e a evidencia mais forte depois do tratamento
-- declarado, porque alguem escreveu aquilo olhando para a pessoa.
--
-- E VEM ANTES DA REGRA DE EMPRESA. "Corretor de Imoveis" tem a palavra
-- "Imoveis" dentro e caia na regra que descarta imobiliarias: Ribamar Neto,
-- Gustavo Valentim e John estavam sem tratamento nenhum por isso -- e por isso
-- a Nay disse "Recebi, Ribamar!" em vez de "Recebi, Sr. Ribamar!".
--
-- MEDIDO ANTES: 13 contatos tem a palavra no nome sem parenteses. A regra
-- acerta os 13 -- 1 estava errado (Fiuza), 10 estavam sem tratamento e 2 ja
-- estavam certos. Nenhum cadastro com "corretora" e tratado por Sr. hoje.
--
-- "Corretor Guarda" e "corretor" continuam sem tratamento: sem nome de gente
-- junto, a Nay chamaria alguem de "Sr. Corretor".
--
-- Gerado por `scratchpad/patch57.py` a partir do que estava NO BANCO.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.nay_tratamento_por_nome(nome text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
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
  -- 0. O PAPEL ESCRITO NO NOME (Tel, 16/09). Ele viu a Nay chamar de "Sra.
  -- Fiuza" um corretor cujo cadastro e "Fiuza - Corretor CRECI 8383": a
  -- palavra "Corretor" estava ali e era ignorada, porque a regra so olhava
  -- dentro de parenteses -- "(Corretor Parceiro)". Sem ela, "Fiuza" caiu na
  -- regra de sufixo, que manda tudo o que termina em -a para o feminino.
  --
  -- Isto vem ANTES da regra de empresa de proposito: "Corretor de Imoveis" tem
  -- a palavra "Imoveis" dentro e caia fora por causa dela. Ribamar, Gustavo e
  -- John estavam sem tratamento nenhum por esse motivo.
  --
  -- A ordem entre as duas linhas importa: "corretora" contem "corretor".
  --
  -- So vale quando ha nome de gente junto: "Corretor Guarda" e "corretor"
  -- continuam sem tratamento, senao a Nay chamaria alguem de "Sr. Corretor".
  primeiro := nay_primeiro_nome(cru);
  n := nay_sem_acento(coalesce(primeiro, ''));
  IF primeiro IS NOT NULL AND length(primeiro) >= 3 AND NOT (n = ANY(lixo)) THEN
    IF cru ~* '\m(corretora|parceira|consultora)\M' THEN RETURN 'Sra.'; END IF;
    IF cru ~* '\m(corretor|parceiro|consultor)\M'   THEN RETURN 'Sr.';  END IF;
  END IF;

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

  -- `primeiro` e `n` ja foram calculados la em cima, no passo 0.
  IF primeiro IS NULL OR length(primeiro) < 3 THEN RETURN NULL; END IF;
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
$function$;
