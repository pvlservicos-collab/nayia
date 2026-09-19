"""
Ponto de entrada único do publicador de grupos.

processar_comando(texto) interpreta um comando do Tel e executa a ação
correspondente, sempre devolvendo o texto de resposta que a Nay manda
de volta no WhatsApp -- confirmação do que foi feito, ou o erro.

Só cola módulos que já existem e são puros (interpretar_comando,
buscar_imovel, montar_destinos, montar_mensagem, enviar_zapi,
liberar_vaga) com o banco real -- nenhum deles muda de comportamento
aqui, só passam a ser chamados com dado de verdade em vez de dado de
teste.

`conexao` é injetável (usado nos testes, com um banco falso) -- quando
não é passada, processar_comando abre uma conexão real e fecha sozinha
ao terminar. Comando não reconhecido nunca abre conexão nenhuma.
"""
from buscar_imovel import buscar_imovel
from enviar_zapi import enviar_imovel, id_da_mensagem
from interpretar_comando import interpretar_comando
from liberar_vaga import descrever_vaga, liberar_codigo
from montar_destinos import carregar_grupos_db, montar_lista_destinos
from montar_mensagem import montar_mensagem

import re

import db


def processar_comando(texto, conexao=None):
    comando = interpretar_comando(texto)
    acao = comando["acao"]

    if acao == "nao_reconhecido":
        return _nao_reconhecido(comando["texto"])

    fechar_ao_sair = conexao is None
    conn = conexao or db.conectar()
    try:
        if acao == "postar_agora":
            return _postar_agora(comando["codigos"], conn)
        if acao == "criar_vaga":
            return _criar_vaga(comando, conn)
        if acao == "liberar_vaga":
            return _liberar_vaga(comando["codigo"], conn)
        if acao == "remover_da_grade":
            return _remover_da_grade(comando["codigo"], conn)
        if acao == "listar_vagas":
            return _listar_vagas(conn)
        if acao == "postar_easy":
            return _postar_easy(comando["codigo"], conn)
        if acao == "envio_recusado":
            return comando["motivo"]
        if acao == "agenda_incompleta":
            # Nao posta: o texto fala de agenda e algo nao foi entendido.
            # Postar em 14 grupos nao tem desfazer; perguntar custa uma frase.
            return ("entendi que e para agendar, mas nao peguei tudo. me manda "
                    "assim: Nay posta o <codigo> terca e quinta as 17h. "
                    "Nao postei nada.")
        if acao == "enviar_para_corretor":
            return _enviar_para_corretor(comando, conn)
        raise RuntimeError(f"ação desconhecida do parser: {acao}")
    finally:
        if fechar_ao_sair:
            conn.close()


def _resolver_corretor(destino, conn):
    """Descobre para quem mandar. Devolve (telefone, nome) ou (None, motivo).

    Ordem: telefone explicito -> nome exato -> primeiro nome unico.
    NUNCA resolve nome ambiguo: mandar a carteira de imoveis para o
    corretor errado nao tem desfazer, e o projeto ja trata "atender uma
    pessoa achando que e outra" como o pior resultado possivel.

    Numero nao cadastrado NAO envia: o Tel decidiu em 31/08 que ela avisa e
    ele manda cadastrar. Um digito trocado mandaria imoveis a um estranho.
    """
    bruto = (destino or "").strip()
    so_digitos = re.sub(r"[^0-9]", "", bruto)

    if len(so_digitos) >= 8:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT telefone, nome FROM corretores "
                " WHERE aprovado AND ativo "
                "   AND right(regexp_replace(telefone,'[^0-9]','','g'),8) = right(%s,8)",
                (so_digitos,),
            )
            achados = cur.fetchall()
        if len(achados) == 1:
            return achados[0]["telefone"], achados[0]["nome"] or bruto
        if not achados:
            return None, (
                f"o numero {bruto} nao esta cadastrado nos corretores. me manda o "
                "nome dele que eu cadastro, ou confirma o numero. nao mandei nada."
            )
        return None, f"achei mais de um corretor com o final {so_digitos[-8:]}. me passa o nome."

    # Limpa artigos e o rotulo "corretor": "o corretor Sergio" -> "Sergio"
    nome = re.sub(r"^(o|a|os|as|pro|pra|para)\s+", "", bruto, flags=re.IGNORECASE).strip()
    nome = re.sub(r"^corretor[ae]?\s+", "", nome, flags=re.IGNORECASE).strip()
    if not nome:
        return None, "para quem eu mando? me diz o nome ou o telefone."

    with conn.cursor() as cur:
        cur.execute(
            "SELECT telefone, nome FROM corretores "
            " WHERE aprovado AND ativo AND coalesce(nome,'') <> '' "
            "   AND (lower(unaccent(nome)) = lower(unaccent(%s)) "
            "        OR lower(unaccent(split_part(btrim(nome),' ',1))) = lower(unaccent(%s)))",
            (nome, nome),
        )
        achados = cur.fetchall()

    if len(achados) == 1:
        return achados[0]["telefone"], achados[0]["nome"]
    if not achados:
        return None, (
            f"nao achei corretor chamado {nome}. me manda o telefone dele que eu "
            "cadastro e ja envio."
        )
    nomes = ", ".join(a["nome"] for a in achados[:4])
    return None, f"tem mais de um {nome}: {nomes}. qual deles? pode me mandar o telefone."


def _enviar_para_corretor(comando, conn):
    """Manda card e TODAS as fotos de cada imovel para um corretor.

    O Tel decidiu em 31/08: quando ele pede, vai o texto e todas as fotos.
    Este envio nao conta no teto de uma mensagem por dia -- quem pediu foi
    ele, nao e cobranca da Nay.
    """
    telefone, nome = _resolver_corretor(comando["destino"], conn)
    if telefone is None:
        return nome  # aqui `nome` carrega o motivo da recusa

    codigos = comando.get("codigos") or []
    if not codigos:
        return (
            f"nao entendi qual imovel mandar para {nome}. me passa o codigo, ou "
            "diga o condominio e se e venda ou locacao."
        )

    # Uma linha ANTES, dizendo o que vem. O Tel apontou em 31/08 que os
    # imoveis chegaram ao Gustavo sem nenhuma palavra em volta -- card e
    # foto caindo do nada. Ele escreveu a frase que queria ver:
    # "Gustavo segue as opcoes que fiquei de te enviar".
    primeiro_nome = (nome or "").split()[0] if (nome or "").strip() else ""
    quantos = len(comando.get("codigos") or [])
    try:
        enviar_texto(
            telefone,
            (f"{primeiro_nome}, segue" if primeiro_nome else "segue")
            + (" as opções que fiquei de te enviar" if quantos > 1
               else " o imóvel que fiquei de te enviar")
            + " 👇"
        )
    except Exception:
        pass  # a frase e cortesia; sem ela o envio continua valendo

    linhas, enviados = [], 0
    for codigo in codigos:
        try:
            imovel = buscar_imovel(codigo)
        except Exception as exc:
            linhas.append(f"{codigo}: nao consegui buscar no site ({exc})")
            continue
        if not imovel:
            linhas.append(f"{codigo}: nao achei esse codigo no site")
            continue

        # NAO reenvia o que ele ja recebeu nas ultimas 12h. O 3495 saiu duas
        # vezes para o Gustavo em 31/08 porque nada olhava `envios` antes.
        # Doze horas, e nao "nunca": reenviar dias depois e legitimo, ele
        # pode ter perdido no meio da conversa.
        with conn.cursor() as cur:
            cur.execute(
                "SELECT 1 FROM envios WHERE codigo = %s AND destino = 'corretor' "
                "  AND right(regexp_replace(telefone,'[^0-9]','','g'),8) = right(%s,8) "
                "  AND enviado_em > now() - interval '12 hours' LIMIT 1",
                (str(codigo), re.sub(r"[^0-9]", "", telefone)),
            )
            if cur.fetchone():
                linhas.append(f"{codigo}: ja mandei para ele hoje, nao repeti")
                continue

        texto_msg = montar_mensagem(imovel, {"aceita_venda": True, "aceita_locacao": True})
        fotos = [f for f in (imovel.get("fotos") or []) if f]
        try:
            resultado = enviar_imovel(telefone, texto_msg, fotos)
        except Exception as exc:
            linhas.append(f"{codigo}: falhou no envio ({exc})")
            continue

        enviados += 1
        # O ID do TEXTO, que é o card -- é ele que o corretor marca ao
        # responder, não a foto.
        _registrar_envio_corretor(conn, codigo, telefone,
                                  id_da_mensagem((resultado or {}).get("texto")))
        linhas.append(f"{codigo} ({imovel.get('condominio') or imovel.get('tipo')}): "
                      f"enviado com {len(fotos)} foto(s)")

    cabecalho = (f"mandei {enviados} imovel(is) para {nome}:" if enviados
                 else f"nao consegui mandar nada para {nome}:")
    return cabecalho + "\n" + "\n".join(linhas)


def _registrar_envio_corretor(conn, codigo, telefone, message_id=None):
    """Deixa rastro em `envios`, como o disparo de grupo passou a fazer.

    GUARDA O message_id (01/09): quando o corretor marca este card, a
    Z-API manda o ID dele em `referenceMessageId`, e `nay_imovel_da_citacao`
    devolve o código por igualdade. Sem o ID guardado, a Nay só pode
    perguntar de qual imóvel se trata.

    Nunca derruba: a mensagem ja saiu quando isto roda.
    """
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO envios (codigo, telefone, destino, message_id) "
                "VALUES (%s,%s,'corretor',%s)",
                (str(codigo), str(telefone), message_id),
            )
        conn.commit()
    except Exception:
        try:
            conn.rollback()
        except Exception:
            pass


def _fotos_para_grupo(imovel, grupo):
    """9 dos 10 grupos recebem só a capa (1a foto); só o grupo com
    todas_fotos=true recebe a lista inteira (decisão do Tel)."""
    fotos = imovel["fotos"]
    if grupo.get("todas_fotos"):
        return fotos
    return fotos[:1]


def _avisos_dados_incompletos(imovel):
    """area==0 ou vagas==0 é dado provavelmente incompleto na extração,
    não motivo pra recusar o post -- só um aviso separado pro Tel
    confirmar com o proprietário."""
    avisos = []
    if imovel.get("area") == 0:
        avisos.append(
            f"Aviso: o imóvel {imovel['codigo']} está com metragem zerada -- "
            "confirme com o proprietário."
        )
    if imovel.get("vagas") == 0:
        avisos.append(
            f"Aviso: o imóvel {imovel['codigo']} está com vagas zeradas -- "
            "confirme com o proprietário."
        )
    return avisos


def _registrar_publicacao(conn, codigo, grupo, message_id=None):
    """Anota que este código foi para este grupo, agora.

    POR QUE ISSO EXISTE (31/08): o corretor responde ao card do grupo
    perguntando "esse está 100% mobiliado?" -- e não havia como saber de
    qual imóvel ele falava. A Z-API não manda mensagem citada (conferido
    em 22 payloads), então a única pista possível é o que a gente mesma
    acabou de postar. Sem este registro, `envios` tinha 20 linhas e
    NENHUMA de grupo: o publicador postava e esquecia.

    Nunca derruba o envio: a mensagem já saiu quando isto roda, e falhar
    aqui não pode fazer o chamador achar que o envio falhou.
    """
    if conn is None:
        return
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO envios (codigo, telefone, destino, grupo_nome, message_id) "
                "VALUES (%s, %s, 'grupo', %s, %s)",
                (str(codigo), str(grupo.get("id_grupo", "")), grupo.get("nome"),
                 message_id),
            )
        conn.commit()
    except Exception:
        try:
            conn.rollback()
        except Exception:
            pass


def _postar_codigo(codigo, grupos, conn=None):
    """Busca um código no site e posta em cada grupo elegível.

    Devolve um dict com o resultado estruturado (sucesso, quantos
    grupos, avisos, ou o erro) -- usado tanto por _postar_agora (comando
    imediato) quanto por disparar_grade.py (vaga agendada), pra não
    duplicar a lógica de buscar + decidir destinos + montar mensagem por
    grupo + enviar em dois lugares (doc 27, Parte 4.3).

    Falha isolada por código: um problema em buscar_imovel ou em
    enviar_imovel vira um resultado de erro, nunca uma exceção que sobe
    -- quem chama para vários códigos (postar_agora, uma vaga com mais
    de 1 código) precisa que a falha de um não trave os outros.
    """
    try:
        imovel = buscar_imovel(codigo)
    except Exception as exc:
        return {
            "codigo": codigo, "sucesso": False, "grupos_atingidos": 0,
            "erro": f"não consegui buscar no site ({exc})", "avisos": [],
        }

    destinos = montar_lista_destinos(imovel, grupos)
    if not destinos:
        return {
            "codigo": codigo, "sucesso": False, "grupos_atingidos": 0,
            "erro": "nenhum grupo elegível (sem valor de venda nem de locação)",
            "avisos": [],
        }

    nome_imovel = imovel.get("condominio") or imovel.get("tipo") or codigo
    grupos_atingidos = 0
    try:
        for grupo in destinos:
            texto_msg = montar_mensagem(imovel, grupo)
            resultado = enviar_imovel(grupo["id_grupo"], texto_msg,
                                      _fotos_para_grupo(imovel, grupo))
            grupos_atingidos += 1  # só conta depois do envio ter dado certo de verdade
            # É o card do GRUPO que o corretor marca e traz para o privado
            # -- foi exatamente isso que o Victor fez em 01/09.
            _registrar_publicacao(conn, codigo, grupo,
                                  id_da_mensagem((resultado or {}).get("texto")))
    except Exception as exc:
        # grupos_atingidos já reflete quantos ENVIOS DE VERDADE aconteceram
        # antes da falha -- zerar isso aqui seria relatar errado e podia
        # levar a reenviar pros grupos que já tinham recebido.
        return {
            "codigo": codigo, "sucesso": False, "grupos_atingidos": grupos_atingidos,
            "nome_imovel": nome_imovel,
            "erro": f"falha ao enviar ({exc})", "avisos": [],
        }

    return {
        "codigo": codigo, "sucesso": True,
        "grupos_atingidos": grupos_atingidos,
        "nome_imovel": nome_imovel,
        "erro": None, "avisos": _avisos_dados_incompletos(imovel),
    }


def _postar_agora(codigos, conn):
    grupos = carregar_grupos_db(conn)
    linhas = []
    for codigo in codigos:
        r = _postar_codigo(codigo, grupos, conn)
        if r["sucesso"]:
            linhas.append(f"{r['codigo']} ({r['nome_imovel']}): postado em {r['grupos_atingidos']} grupo(s)")
            linhas.extend(r["avisos"])
        elif r["grupos_atingidos"] > 0:
            linhas.append(
                f"{r['codigo']} ({r['nome_imovel']}): postado em {r['grupos_atingidos']} "
                f"grupo(s) antes de falhar -- {r['erro']}"
            )
        else:
            linhas.append(f"{r['codigo']}: {r['erro']}")

    return "Pronto:\n" + "\n".join(linhas)


def _criar_vaga(comando, conn):
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO vagas (horario, tipo_recorrencia, dias_semana, data_unica, codigos) "
            "VALUES (%s, %s, %s, %s, %s) RETURNING id",
            (
                comando["horario"],
                comando["tipo_recorrencia"],
                comando.get("dias_semana"),
                comando.get("data_unica"),
                comando["codigos"],
            ),
        )
        vaga_id = cur.fetchone()["id"]
    conn.commit()

    vaga = {
        "tipo_recorrencia": comando["tipo_recorrencia"],
        "horario": comando["horario"],
        "dias_semana": comando.get("dias_semana"),
        "data_unica": comando.get("data_unica"),
    }
    codigos_txt = ", ".join(comando["codigos"])
    return f"Vaga #{vaga_id} criada: {descrever_vaga(vaga)}, códigos {codigos_txt}."


def _tirar_codigo_das_vagas(codigo, conn):
    """Tira um código de toda vaga onde ele estiver e devolve as
    mudanças aplicadas (lista vazia se não estava em nenhuma).

    Trabalho de banco compartilhado por liberar_vaga (VENDEU/ALUGOU) e
    remover_da_grade (TIRA/REMOVE): na tabela as duas fazem exatamente
    a mesma coisa, o que muda é só o significado pro Tel. Escrita num
    lugar só pra não divergirem sem ninguém perceber (doc 27, Parte
    4.3) -- o dia em que "vendeu" também marcar o imóvel no site, a
    diferença vai estar no handler, não aqui.
    """
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id, horario, tipo_recorrencia, dias_semana, data_unica, codigos FROM vagas"
        )
        vagas = cur.fetchall()

    mudancas = liberar_codigo(vagas, codigo)
    if not mudancas:
        return mudancas  # nada a atualizar -- não commita à toa

    with conn.cursor() as cur:
        for m in mudancas:
            cur.execute(
                "UPDATE vagas SET codigos = %s WHERE id = %s",
                (m["codigos_depois"], m["vaga_id"]),
            )
    conn.commit()
    return mudancas


def _marcar_indisponivel(codigo, conn):
    """Tira o imóvel da oferta e mata o que dependia dele.

    Sem isto, `VENDEU` só limpava a grade: as buscas usam
    `coalesce(disponivel, true)` e continuavam oferecendo, o lembrete
    continuava cobrando e a entrega pendente continuava devendo.
    """
    resumo = []
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE imoveis SET disponivel = false, sincronizado_em = now() "
            " WHERE codigo::text = %s AND coalesce(disponivel, true) RETURNING codigo",
            (str(codigo),))
        if cur.fetchone():
            resumo.append("marquei como indisponível")

        cur.execute(
            "UPDATE lembrete SET estado='morto', motivo_fim='imovel saiu do mercado', "
            "atualizado_em=now() WHERE codigo = %s AND estado IN "
            "('agendado','enviado','congelado')", (str(codigo),))
        if cur.rowcount:
            resumo.append(f"cancelei {cur.rowcount} lembrete(s)")

        cur.execute(
            "UPDATE entrega_pendente SET estado='cancelada' "
            " WHERE codigo = %s AND estado='devendo'", (str(codigo),))
        if cur.rowcount:
            resumo.append(f"cancelei {cur.rowcount} entrega(s) pendente(s)")

        # Esquece o que sabia do imóvel. Conhecimento de imóvel vendido,
        # reusado depois, é pior que conhecimento nenhum: parece atual e
        # não é. Decisão do Tel em 01/09 -- "só apagar quando o imóvel não
        # estiver disponível".
        cur.execute("SELECT nay_esquecer_imovel(%s) AS n", (str(codigo),))
        n = (cur.fetchone() or {}).get("n") or 0
        if n:
            resumo.append(f"esqueci {n} informação(ões) que eu sabia dele")
    conn.commit()
    return resumo


def _liberar_vaga(codigo, conn):
    mudancas = _tirar_codigo_das_vagas(codigo, conn)
    extra = _marcar_indisponivel(codigo, conn)

    if not mudancas and not extra:
        return f"{codigo} não estava em nenhuma vaga e já estava fora da oferta."

    linhas = [f"{codigo} removido de {len(mudancas)} vaga(s)." if mudancas
              else f"{codigo} não estava em nenhuma vaga."]
    linhas.extend(m["aviso"] for m in mudancas if m["aviso"])
    if extra:
        linhas.append("Também " + ", ".join(extra) + ".")
    return "\n".join(linhas)


def _remover_da_grade(codigo, conn):
    """Mesma escrita no banco que _liberar_vaga, resposta diferente de
    propósito: não afirma nem sugere que o imóvel foi vendido/alugado,
    porque TIRA/REMOVE é só reorganização de horário."""
    mudancas = _tirar_codigo_das_vagas(codigo, conn)
    if not mudancas:
        return f"{codigo} não estava na grade."

    linhas = [f"{codigo} removido da grade."]
    linhas.extend(m["aviso"] for m in mudancas if m["aviso"])
    return "\n".join(linhas)


def _listar_vagas(conn):
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id, horario, tipo_recorrencia, dias_semana, data_unica, codigos "
            "FROM vagas ORDER BY horario"
        )
        vagas = cur.fetchall()

    if not vagas:
        return "Nenhuma vaga cadastrada ainda."

    linhas = ["Grade atual:"]
    for vaga in vagas:
        codigos_txt = ", ".join(vaga["codigos"]) if vaga["codigos"] else "vaga livre"
        linhas.append(f"- {descrever_vaga(vaga)}: {codigos_txt}")
    return "\n".join(linhas)


def _postar_easy(codigo, conn):
    """Comando dedicado do grupo todas_fotos=true (hoje só "IMÓVEIS
    PARA ANUNCIAR EASY"), fora do fluxo normal (Mudança 2). Cada
    código só entra uma vez. Sem checagem de aceita_venda/
    aceita_locacao pro grupo Easy -- o pedido não previu esse filtro
    pra este comando, então não inventei um.

    Condição de corrida real vista em produção (25/08): a versão
    anterior fazia SELECT (checa) -> busca+envia -> INSERT (grava),
    com uma janela de segundos/minutos entre checar e gravar. Duas
    chamadas pro mesmo código nesse intervalo passavam as duas pela
    checagem e postavam as duas. Conserto: reserva o código PRIMEIRO,
    de forma atômica (INSERT ... ON CONFLICT DO NOTHING ... RETURNING)
    -- o Postgres serializa INSERTs concorrentes na mesma chave
    primária, então não existe mais janela entre checar e gravar
    quando é a mesma operação. A reserva é commitada na hora, antes de
    buscar/enviar (que pode levar minutos) -- segurar a transação
    aberta até o fim do envio trocaria "corrida" por "trava a fila
    inteira por minutos a cada chamada".

    Efeito colateral aceito, não resolvido aqui: se buscar_imovel ou
    enviar_imovel falhar DEPOIS da reserva já commitada, o código fica
    marcado como postado mesmo sem ter enviado nada de verdade -- não
    existe hoje um comando pra desmarcar. É um problema diferente do
    da corrida (falha depois de reservar, não corrida entre reservas).

    Se precisar reverter uma reserva travada dessas manualmente, rode
    isto direto no banco (confirme que realmente não postou nada antes
    de apagar -- isso libera o código pra postar_easy de novo):

        DELETE FROM easy_publicacoes WHERE codigo = 'X';
    """
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO easy_publicacoes (codigo) VALUES (%s) "
            "ON CONFLICT (codigo) DO NOTHING RETURNING codigo",
            (codigo,),
        )
        reservado = cur.fetchone()

    if not reservado:
        conn.rollback()
        with conn.cursor() as cur:
            cur.execute("SELECT publicado_em FROM easy_publicacoes WHERE codigo = %s", (codigo,))
            linha = cur.fetchone()
        data = linha["publicado_em"].strftime("%d/%m/%Y")
        return f"{codigo} já foi postado no Easy em {data}. Não postei de novo."

    conn.commit()  # reserva valendo já -- ninguém mais reserva este código

    try:
        imovel = buscar_imovel(codigo)
    except Exception as exc:
        return f"{codigo}: não consegui buscar no site ({exc})"

    grupos_easy = [g for g in carregar_grupos_db(conn) if g.get("todas_fotos")]
    if not grupos_easy:
        return f"{codigo}: nenhum grupo com todas_fotos=true configurado no banco."

    nome_imovel = imovel.get("condominio") or imovel.get("tipo") or codigo

    # Falha isolada, igual _postar_codigo faz desde o doc 29. Este laço
    # era o único caminho de envio do projeto SEM proteção: uma exceção
    # aqui subia até servidor.py, que devolve 500 e retorna ANTES de
    # avisar o Tel pelo WhatsApp -- ou seja, metade da mensagem saía no
    # grupo e ele não ficava sabendo de nada.
    #
    # O Easy é o caso mais exposto justamente por levar TODAS as fotos
    # (11 no código 2943, 6s de pausa entre cada): a janela em que a
    # Z-API pode falhar no meio é de mais de um minuto.
    grupos_atingidos = 0
    try:
        for grupo in grupos_easy:
            texto_msg = montar_mensagem(imovel, grupo)
            resultado = enviar_imovel(grupo["id_grupo"], texto_msg,
                                      _fotos_para_grupo(imovel, grupo))
            grupos_atingidos += 1  # só conta depois do envio inteiro ter dado certo
            # O EASY TAMBÉM PRECISA SER REGISTRADO (01/09). Ele era o único
            # caminho de envio que postava e esquecia: sem linha em `envios`
            # não há `message_id`, e sem `message_id` a citação não resolve.
            # A Waldyrene respondeu ao card do Smart Tower Itapuranga postado
            # aqui, escreveu "ainda disponivel", e a Nay teve que perguntar de
            # qual imóvel ela falava -- com o dado na mão e sem onde procurar.
            _registrar_publicacao(conn, codigo, grupo,
                                  id_da_mensagem((resultado or {}).get("texto")))
    except Exception as exc:
        # Deliberadamente menciona o envio PARCIAL: grupos_atingidos conta
        # só os grupos que receberam tudo, então o grupo em que falhou
        # pode ter recebido o texto e parte das fotos sem aparecer nesta
        # contagem. Dizer "0 grupos" e calar isso faria o Tel achar que
        # nada saiu, quando saiu -- e WhatsApp não tem desfazer.
        return (
            f"{codigo} ({nome_imovel}): falhei no meio do envio pro Easy -- {exc}. "
            f"{grupos_atingidos} grupo(s) receberam tudo; o grupo onde parou pode "
            f"ter recebido o texto e parte das fotos. O código segue marcado como "
            f"postado, então não sai de novo por engano -- me avise se quiser liberar."
        )

    linhas = [
        f"{codigo} ({nome_imovel}) postado no Easy, com todas as fotos, "
        f"em {len(grupos_easy)} grupo(s)."
    ]
    linhas.extend(_avisos_dados_incompletos(imovel))
    return "\n".join(linhas)


def _nao_reconhecido(texto_original):
    return (
        f'Não entendi o comando "{texto_original}". '
        'Exemplos que eu reconheço: "posta o 5750", '
        '"posta o 5750 todo dia às 14h", '
        '"posta 5750, 5751 e 5752 terça e quinta às 9h", '
        '"VENDEU 5750", "ALUGOU 5750", "tira o 5750", "VAGAS", '
        '"publica no anunciar easy o 5750".'
    )
