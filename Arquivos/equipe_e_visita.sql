-- Equipe (quem acompanha visita) e a regra de decisão da visita.
--
-- POR QUE UMA TABELA NOVA E NÃO `corretores`: o Fernando não é corretor.
-- Se entrasse em `corretores`, o porteiro de 29/08 passaria a atendê-lo
-- como corretor -- ele receberia card de imóvel, poderia pedir visita, e
-- o `dados_do_corretor` pediria CRECI dele. Papel diferente, tabela
-- diferente.
--
-- O CPF fica AQUI, no banco, e nunca em arquivo do repositório: é dado
-- pessoal e o repositório vai para o GitHub. O INSERT do Fernando é
-- rodado à mão, fora deste arquivo.
--
-- TELEFONE, o detalhe que morde: a Z-API entrega número brasileiro ora
-- com o 9 na frente (5592 9 9201 9498, 13 dígitos) ora sem (12 dígitos).
-- Os corretores no banco estão com 12. Por isso a comparação nunca é
-- igualdade crua: `nay_e_da_equipe` casa pelos 8 últimos dígitos, que
-- não mudam nos dois formatos.

CREATE TABLE IF NOT EXISTS equipe (
  telefone  text PRIMARY KEY,
  nome      text NOT NULL,
  papel     text NOT NULL,
  cpf       text,
  ativo     boolean NOT NULL DEFAULT true,
  criado_em timestamptz NOT NULL DEFAULT now()
);

-- Casa telefone da equipe tolerando o 9 extra do celular brasileiro.
CREATE OR REPLACE FUNCTION nay_e_da_equipe(p_telefone text)
RETURNS TABLE(nome text, papel text)
LANGUAGE sql STABLE AS $fn$
  SELECT e.nome, e.papel
    FROM equipe e
   WHERE e.ativo
     AND right(regexp_replace(e.telefone,'[^0-9]','','g'), 8)
       = right(regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g'), 8)
   LIMIT 1;
$fn$;

-- O proprietário acompanha a visita neste imóvel? É o que decide se a
-- regra das 2 horas vale. NULL = ainda não se sabe, e nesse caso ela
-- pergunta ao Tel em vez de supor.
ALTER TABLE imovel_privado
  ADD COLUMN IF NOT EXISTS proprietario_acompanha boolean;

-- --------------------------------------------------------------------
-- A decisão da visita, em um lugar só.
--
-- Regras ditadas pelo Tel em 29/08:
--  - visita em que o PROPRIETÁRIO acompanha precisa de aviso com
--    antecedência, nunca em cima da hora;
--  - menos de 2 horas + proprietário acompanha  -> aciona o Tel, e ao
--    corretor ela diz que vai verificar porque está em cima;
--  - menos de 2 horas SEM o proprietário (temos chave, ou fechadura
--    eletrônica com senha) -> segue o caminho normal, só o Fernando;
--  - não se sabe como funciona a visita -> pergunta ao Tel, não supõe.
--
-- Devolve `acao` para o fluxo decidir, e `texto_pronto` com o que ela
-- diz. O modelo não pondera a regra: ela chega pronta.
CREATE OR REPLACE FUNCTION nay_avaliar_visita(
  p_codigo text,
  p_quando text,
  p_nome_corretor text
) RETURNS TABLE(acao text, texto_pronto text, instrucao_para_voce text)
LANGUAGE plpgsql AS $fn$
DECLARE
  v_cod   int := NULLIF(regexp_replace(coalesce(p_codigo,''),'[^0-9]','','g'),'')::int;
  v_nome  text := coalesce(NULLIF(btrim(coalesce(p_nome_corretor,'')),''), 'corretor');
  v_quando timestamptz;
  v_horas numeric;
  v_como  text;
  v_acomp boolean;
  v_existe boolean;
BEGIN
  IF v_cod IS NULL THEN
    RETURN QUERY SELECT 'perguntar_codigo'::text,
      'de qual imovel e a visita? me passa o codigo'::text,
      'peca o codigo antes de qualquer coisa.'::text;
    RETURN;
  END IF;

  SELECT true, btrim(coalesce(p.como_funciona_visita,'')), p.proprietario_acompanha
    INTO v_existe, v_como, v_acomp
    FROM imovel_privado p WHERE p.codigo = v_cod;

  -- Ainda não sabemos como se visita este imóvel: não inventa.
  IF NOT coalesce(v_existe,false) OR coalesce(v_como,'') = '' OR v_acomp IS NULL THEN
    RETURN QUERY SELECT 'perguntar_ao_tel'::text,
      (v_nome || ', vou verificar como conseguimos fazer a visita e ja te aviso')::text,
      ('nao esta registrado como funciona a visita no imovel ' || v_cod ||
       '. Escale ao Tel perguntando: como funciona a visita no ' || v_cod ||
       '? o proprietario acompanha, temos chave, ou e fechadura eletronica? ' ||
       'Quando ele responder, chame guardar_como_funciona_a_visita.')::text;
    RETURN;
  END IF;

  -- Horário proposto. Texto livre não vira suposição: se não der para
  -- interpretar, ela pergunta em vez de assumir.
  BEGIN
    v_quando := p_quando::timestamptz;
  EXCEPTION WHEN OTHERS THEN
    v_quando := NULL;
  END;

  IF v_quando IS NULL THEN
    RETURN QUERY SELECT 'perguntar_horario'::text,
      (v_nome || ', que horas voce quer visitar?')::text,
      'nao deu para entender o horario. pergunte antes de avaliar.'::text;
    RETURN;
  END IF;

  v_horas := EXTRACT(EPOCH FROM (v_quando - now())) / 3600.0;

  IF v_horas < 0 THEN
    RETURN QUERY SELECT 'perguntar_horario'::text,
      (v_nome || ', esse horario ja passou. qual outro horario fica bom?')::text,
      'o horario pedido esta no passado.'::text;
    RETURN;
  END IF;

  -- Em cima da hora E o proprietário acompanha: o Tel decide.
  IF v_horas < 2 AND v_acomp THEN
    RETURN QUERY SELECT 'escalar_em_cima'::text,
      (v_nome || ', eu vou verificar se vamos conseguir fazer a visita, porque como esta ' ||
       'um pouco em cima tenho que confirmar com o proprietario')::text,
      ('faltam menos de 2 horas e neste imovel o proprietario acompanha. ' ||
       'Diga ao corretor exatamente o texto_pronto e escale ao Tel com o horario pedido, ' ||
       'dizendo que e visita em cima da hora com proprietario. Nao prometa a visita.')::text;
    RETURN;
  END IF;

  -- Caminho normal: confirma com o Fernando.
  RETURN QUERY SELECT 'pedir_fernando'::text,
    (v_nome || ', vou confirmar a disponibilidade e ja te aviso')::text,
    ('a visita pode seguir o caminho normal. Como funciona aqui: ' || v_como ||
     '. Escale ao Tel com o horario pedido para confirmar o Fernando. ' ||
     'Nao diga ao corretor que esta confirmado antes de voltar a resposta.')::text;
END;
$fn$;
