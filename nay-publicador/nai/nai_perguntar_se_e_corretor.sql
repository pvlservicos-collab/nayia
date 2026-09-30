CREATE OR REPLACE FUNCTION public.nai_perguntar_se_e_corretor()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  c        nai_contato;
  v_nova   boolean;
  v_texto  text;
BEGIN
  SELECT * INTO c FROM nai_contato WHERE id = NEW.contato_id;
  IF c.id IS NULL THEN RETURN NEW; END IF;

  -- So a PRIMEIRA vez. Se ja perguntou, a porta ja devolveu "esperando o Tel".
  INSERT INTO nai_corretor_pergunta (chave, telefone, nome, ultimo_texto, turno_id)
  VALUES (c.chave, c.telefone, coalesce(c.nome_completo, c.nome_whatsapp), left(NEW.texto, 300), NEW.id)
  ON CONFLICT (chave) DO NOTHING
  RETURNING true INTO v_nova;

  IF NOT coalesce(v_nova, false) THEN RETURN NEW; END IF;

  -- Sem emoji: texto que sai de funcao nao passa pelo filtro do modelo.
  v_texto := 'Chegou mensagem de quem NÃO está nos grupos de corretores:' || E'\n\n'
          || coalesce(nullif(btrim(coalesce(c.nome_completo, c.nome_whatsapp, '')), ''), 'sem nome')
          || ' - ' || nai_fone_fmt(c.telefone) || E'\n'
          || '"' || left(coalesce(NEW.texto, ''), 300) || '"' || E'\n\n'
          || 'Ela não respondeu. É corretor? Responda aqui:' || E'\n'
          || 'CORRETOR ' || nai_fone_fmt(c.telefone) || '  - ela passa a atender' || E'\n'
          || 'NAO CORRETOR ' || nai_fone_fmt(c.telefone) || '  - ela nunca responde';

  PERFORM nai_avisar_tel(NEW.id, NULL, v_texto, 'corretor fora da lista');
  RETURN NEW;
EXCEPTION WHEN others THEN
  -- Este gatilho roda DENTRO do nai_abrir_turno. Se o aviso falhar, o turno do
  -- corretor nao pode morrer junto: perder a pergunta e ruim, derrubar a
  -- entrada da mensagem e pior.
  RAISE WARNING 'nai_perguntar_se_e_corretor falhou no turno %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$function$
;
