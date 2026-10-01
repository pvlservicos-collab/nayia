-- 257 (01/10/2026): O IMÓVEL DA PERGUNTA, NÃO O DA CONVERSA.
-- Pedro: "ela perguntou a taxa de condomínio do Vitta e ela respondeu de outro
-- que tinha enviado anteriormente... quando o cara faz uma pergunta ela tem que
-- identificar o imóvel da pergunta também, para saber se é o mesmo".
--
-- O CASO (contato 10643, Patricia): 14:20 a Nay mandou o Acquarelle (1125);
-- 17:48 ele perguntou "qual valor da taxa de condomínio do vitta club house?" e
-- às 17:49 ela respondeu a taxa do ACQUARELLE ("já está inclusa no aluguel...
-- 98 m²... 7º andar"). O certo era 422 (o 5698, Vitta Club House).
--
-- POR QUE PASSOU: a nai_imovel_da_conversa tem um passo (1b) que aceita o nome
-- do condomínio, mas só quando o nome aponta para UM imóvel -- e o Vitta Club
-- House tem oito. E o passo 3 procura o nome só ENTRE os imóveis que estão na
-- mesa. Com o nome caindo fora dos dois, ela foi para o passo 4 e devolveu o
-- imóvel do último turno: o Acquarelle.
--
-- A REGRA NOVA: se a pergunta cita um condomínio e NENHUM imóvel da mesa é
-- desse condomínio, o imóvel da conversa é NULL -- ela pergunta de qual é, em
-- vez de responder sobre outro. Responder errado é pior do que perguntar.
--
-- O CASADOR É O ESTRITO (crm_condominio_pelo_texto, 246: o núcleo do nome com 4
-- letras ou mais, na borda da palavra), e ainda tira o condomínio cujo nome é
-- BAIRRO ou AVENIDA. Medido no corpus de 36 h (150 mensagens recebidas):
--   * o casador antigo (nai_imovel_pelo_condominio, que casa por som) achava
--     condomínio em "a cozinha, a geladeira, gostaria de ver melhor", em "mas
--     preciso ver melhor nas fotos" e em "sua IA está respondendo confusa" --
--     com ele, esta regra calaria a Nay à toa;
--   * o estrito não acha nada nos três, e acha o Vitta Club House;
--   * sem a exclusão de bairro/avenida, "pelo Adrianópolis" viraria o
--     Residencial Adrianópolis e "região da Torquato Tapajós" o Residencial
--     Tapajós -- os dois existem no cadastro de condomínios.
-- Custo medido do casador estrito: 28 ms, e ele só roda quando há imóvel na mesa
-- e ela está a ponto de usar o do último turno.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE d text := pg_get_functiondef(p_fn); n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 50); END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

-- o condomínio que a PERGUNTA cita, com confiança: núcleo do nome (4+ letras,
-- na borda da palavra) e nunca um nome que é bairro ou avenida.
CREATE OR REPLACE FUNCTION public.nai_condominio_da_pergunta(p_texto text)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  SELECT c.id
    FROM crm_condominio_pelo_texto(p_texto) c
   WHERE NOT EXISTS (SELECT 1 FROM bairro_normal b
                      WHERE b.normal = nay_normalizar_lugar(nai_condominio_nucleo(c.nome), true))
     AND NOT EXISTS (SELECT 1 FROM nai_lugar_avenida a
                      WHERE nay_sem_acento(lower(a.nome)) LIKE '%' || nay_sem_acento(lower(nai_condominio_nucleo(c.nome))) || '%')
   LIMIT 1;
$function$;
COMMENT ON FUNCTION nai_condominio_da_pergunta(text) IS
  '257: o condomínio que a pergunta cita, pelo núcleo do nome; nome que é bairro ou avenida não conta';

SELECT pg_temp.trocar('nai_imovel_da_conversa(bigint,text)'::regprocedure,
$de$  IF coalesce(array_length(v_cods, 1), 0) = 0 THEN RETURN NULL; END IF;

  -- 3. ele chamou pelo NOME ("me manda foto do arezzo")$de$,
$para$  IF coalesce(array_length(v_cods, 1), 0) = 0 THEN RETURN NULL; END IF;

  -- 2b. 257: A PERGUNTA CITA OUTRO CONDOMÍNIO. Se o nome que ele escreveu é de
  -- um condomínio e NENHUM imóvel da mesa é desse condomínio, não há imóvel da
  -- conversa: ela pergunta de qual é. Era aqui que a taxa do Acquarelle saía
  -- como resposta da pergunta sobre o Vitta Club House (01/10, 17:48).
  IF btrim(q) <> '' THEN
    DECLARE v_outro int;
    BEGIN
      v_outro := nai_condominio_da_pergunta(p_texto);
      IF v_outro IS NOT NULL AND NOT EXISTS (
           SELECT 1 FROM imoveis i, condominios cd
            WHERE i.codigo = ANY (v_cods) AND cd.id = v_outro
              AND (i.condo_id = cd.id
                   OR nay_sem_acento(lower(btrim(coalesce(i.condominio_nome, '')))) = nay_sem_acento(lower(btrim(cd.nome))))) THEN
        RETURN NULL;
      END IF;
    END;
  END IF;

  -- 3. ele chamou pelo NOME ("me manda foto do arezzo")$para$);
COMMIT;
