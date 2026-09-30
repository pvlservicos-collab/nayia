CREATE OR REPLACE FUNCTION public.nai_sem_pergunta_de_identidade(p text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  t text := coalesce(p, '');
  -- A PERGUNTA QUE ELA NUNCA FAZ (Tel, 16/09): "ficou perguntando quem era que
  -- estava falando, sendo que tem o nome no cadastro -- e mesmo se nao tiver,
  -- nao precisamos desse dado, so saber do imovel da pessoa. Quero que isso
  -- esteja como regra fundamental."
  --
  -- A frase que ele viu, as 15:06: "Antes de combinarmos o dia e o horario,
  -- com quem eu falo e qual e o codigo do imovel?" -- e a pessoa respondeu
  -- "Meu nome e Andresa", que e o dado que nao interessa a ninguem.
  --
  -- Os acentos entram nos padroes porque o texto dela vem acentuado: sem isso,
  -- "Qual E o seu nome?" passava batido enquanto "Qual e o seu nome?" saia.
  quem text := '(com quem (eu |eu estou |estou )?(falo|falando)'
            || '|quem (esta|está|ta|tá) (falando|ai|aí)'
            || '|quem (e|é|eh) que (esta|está|ta|tá) falando'
            || '|posso saber com quem (falo|estou falando))';
  nome text := '((qual|que) (e|é|eh)?\s*(o )?(seu|teu) nome'
            || '|como (e|é|eh)?\s*(o )?(seu|teu) nome'
            || '|(me )?(diz|diga|informa|fala|passa|manda) (o |qual )?(seu|teu) nome'
            || '|posso saber (o )?(seu|teu) nome'
            || '|(seu|teu) nome( completo)?,? por favor)';
BEGIN
  IF btrim(t) = '' THEN RETURN t; END IF;

  -- O NOME DO VISITANTE E OUTRA COISA: o fluxo da visita pede, de proposito, o
  -- nome e o CPF de quem vai entrar no imovel, e o CRECI do corretor. Se a
  -- frase fala disso, ela passa inteira.
  IF lower(unaccent(t)) ~ '(visitante|cliente|locatari|inquilin|quem vai (visitar|entrar)|acompanha|creci|cpf)' THEN
    RETURN t;
  END IF;

  -- 1) "Me diz SEU NOME e o codigo" -- o verbo fica, so o nome sai. Vem
  --    PRIMEIRO: se as regras de baixo rodassem antes, levariam o "Me diz"
  --    junto e sobraria "Certo! o codigo do imovel."
  t := regexp_replace(t, '(?i)\s*(o |qual )?(seu|teu) nome\s*,?\s+e\s+', ' ', 'g');

  -- 2) A pergunta com o conectivo que vem depois: "..., com quem eu falo E
  --    qual e o codigo?" -> "..., qual e o codigo?"
  --    A virgula da frente NAO e consumida -- ela separa o que fica.
  t := regexp_replace(t, '(?i)\s*' || quem || '\s*,?\s+e\s+', ' ', 'g');
  t := regexp_replace(t, '(?i)\s*' || nome || '\s*,?\s+e\s+', ' ', 'g');

  -- 3) A pergunta depois de um conectivo: "me diz o codigo e seu nome"
  t := regexp_replace(t, '(?i)\s*,?\s+e\s+' || quem, '', 'g');
  t := regexp_replace(t, '(?i)\s*,?\s+e\s+' || nome, '', 'g');

  -- 4) A pergunta sozinha, com o ponto de interrogacao dela.
  t := regexp_replace(t, '(?i)\s*,?\s*' || quem || '\s*[?.!]*', '', 'g');
  t := regexp_replace(t, '(?i)\s*,?\s*' || nome || '\s*[?.!]*', '', 'g');

  -- 5) Costura: o que sobrou de pontuacao e espaco.
  --
  -- SO ESPACO E TAB, NUNCA QUEBRA DE LINHA. A primeira versao usava `\s`, que
  -- inclui o fim de linha -- e a bateria pegou na hora: a ficha do imovel, que
  -- o Tel quer em linhas separadas ("Tem 3 quartos." / "Tem 2 banheiros."),
  -- virava um paragrafo so. Tres testes de formato cairam de uma vez.
  t := regexp_replace(t, '(?i)^[ \t]*,?[ \t]*(por favor|por gentileza)[ \t]*[?.!]*[ \t]*$', '', 'n');
  t := regexp_replace(t, '[ \t]{2,}', ' ', 'g');
  t := regexp_replace(t, '[ \t]+([,.!?])', '\1', 'g');
  t := regexp_replace(t, ',[ \t]*([.!?])', '\1', 'g');
  t := regexp_replace(t, '(?m)^[ \t]*[,;:][ \t]*', '', 'g');
  t := regexp_replace(t, '(?m)^[ \t]+', '', 'g');
  t := regexp_replace(t, '\n{3,}', chr(10) || chr(10), 'g');

  RETURN btrim(t);
END;
$function$
;
