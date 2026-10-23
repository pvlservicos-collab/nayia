"""A autorização do Tel no grupo (Pedro, 23/10/2026): as dúvidas primeiro no grupo, o pedido para falar com o contato,
e o privado só depois do "pode". Sem banco, sem rede e sem modelo de verdade."""
import json

from cadastro import autorizacao, campos, envio, fluxo, modelo

FICHA = {"tipo": "Apartamento", "condominio": "Riviera Francesa", "condo_id": 7, "bairro": "Ponta Negra",
         "valor_venda": 970000, "_fotos": 5}


def test_o_tel_manda_pular_ou_perguntar_so_algumas():
    ctx = {"papel_conhecido": True, "papel": "corretor"}
    todas = campos.faltam(FICHA, ctx)
    assert "andar" in todas and "quartos" in todas
    assert "andar" not in campos.faltam({**FICHA, "_pular": ["andar"]}, ctx)
    assert campos.faltam({**FICHA, "_so_perguntar": ["quartos", "area"]}, ctx) == [k for k in todas if k in ("quartos", "area")]


def _modelo_responde(saida: dict):
    def chamar(corpo):
        chamar.corpo = corpo
        return {"output": [{"type": "message", "content": [{"type": "output_text", "text": json.dumps(saida)}]}]}
    return chamar


def test_a_decisao_do_tel_so_aceita_as_duvidas_da_lista():
    ch = _modelo_responde({"decisao": "autoriza", "so_perguntar": [], "pular": ["andar", "inventada"]})
    d = modelo.ler_decisao("IMÓVEL 9057", {"andar": "andar", "quartos": "quartos e suítes"}, "pode, só não pergunta o andar", ch)
    assert d == {"decisao": "autoriza", "so_perguntar": [], "pular": ["andar"]}
    schema = ch.corpo["text"]["format"]["schema"]
    assert schema["properties"]["pular"]["items"]["enum"] == ["andar", "quartos"]


class _Falso:
    def __init__(self):
        self.grupo, self.gravado, self.concluido = [], {}, None

    def ligar(self):
        self._antes = (fluxo.gravar, fluxo.contexto, fluxo.concluir, fluxo.no_horario, envio.grupo)
        fluxo.gravar = lambda conn, cid, **k: self.gravado.update(k)
        fluxo.contexto = lambda conn, c: {"papel_conhecido": True, "papel": "corretor"}
        fluxo.concluir = lambda conn, c, como, despedir=True: setattr(self, "concluido", (como, despedir))
        fluxo.no_horario = lambda q=None: True
        envio.grupo = lambda conn, texto, cid=None, citar=None: self.grupo.append(texto) or "m1"
        return self

    def desligar(self):
        fluxo.gravar, fluxo.contexto, fluxo.concluir, fluxo.no_horario, envio.grupo = self._antes


def _c(**k):
    return {"id": 1, "codigo": 9057, "estado": "na_fila", "contato_nome": "Ana", "contato_tel": "5592988887777",
            "papel": "corretor", "canal": "leads", "ficha": {**FICHA, "_autorizacao": "pedida"}, **k}


def test_sem_o_pode_do_tel_o_privado_nao_comeca():
    f = _Falso().ligar()
    try:
        assert autorizacao.precisa_autorizar(None, _c())
        assert not autorizacao.precisa_autorizar(None, _c(ficha={**FICHA, "_autorizacao": "sim"}))
        assert "Ana, corretor" in autorizacao.texto_do_pedido(None, _c()) and "número de leads" in autorizacao.texto_do_pedido(None, _c())
    finally:
        f.desligar()


def test_o_pedido_marca_quem_mandou_e_so_ele_ou_o_tel_decidem():
    """Pedro, 23/10: "é melhor ele perguntar do número que enviou as primeiras informações de imóvel e não fixar isso
    no número do Tel"."""
    from cadastro import banco
    f = _Falso().ligar()
    antes = banco.uma
    banco.uma = lambda conn, sql, params=None: {"t": "559294717316"}           # nai_cfg('tel_telefone')
    try:
        c = _c(ficha={**FICHA, "_autorizacao": "pedida", "_quem_mandou": {"tel": "559285956408", "nome": "Imob Easy"}})
        assert autorizacao.texto_do_pedido(None, c).startswith("🙋 @559285956408, posso falar com Ana")
        assert autorizacao.pode_decidir(None, c, "559285956408")       # quem mandou (o 8595 da equipe)
        assert autorizacao.pode_decidir(None, c, "5592994717316")      # o Tel, com o 9 a mais
        assert not autorizacao.pode_decidir(None, c, "559281680503")   # outra pessoa no grupo
        assert autorizacao.texto_do_pedido(None, _c()).startswith("🙋 Tel, posso")   # ficha antiga, sem quem mandou
    finally:
        banco.uma = antes
        f.desligar()


def test_pode_libera_e_ela_diz_o_que_vai_perguntar():
    f = _Falso().ligar()
    try:
        assert autorizacao.aplicar(None, _c(), {"decisao": "autoriza", "so_perguntar": [], "pular": ["andar"]}, "x")
        assert f.gravado["ficha"]["_autorizacao"] == "sim" and f.gravado["ficha"]["_pular"] == ["andar"]
        assert f.grupo[-1].startswith("Certo! Vou perguntar a Ana:") and "andar" not in f.grupo[-1]
        assert f.concluido is None
    finally:
        f.desligar()


def test_nao_fecha_sem_falar_com_ninguem_e_espera_segura():
    f = _Falso().ligar()
    try:
        autorizacao.aplicar(None, _c(), {"decisao": "nao_autoriza", "so_perguntar": [], "pular": []}, "x")
        assert f.gravado["ficha"]["_autorizacao"] == "nao" and f.concluido == ("concluido", False)
        f.concluido = None
        autorizacao.aplicar(None, _c(), {"decisao": "esperar", "so_perguntar": [], "pular": []}, "x")
        assert f.concluido is None and "espero" in f.grupo[-1]
        assert not autorizacao.aplicar(None, _c(), {"decisao": "nenhuma", "so_perguntar": [], "pular": []}, "x")
    finally:
        f.desligar()
