"""O checklist da visita da Parceria no grupo (Pedro, 20/10/2026). Só o texto; o banco é provado no ensaio da 444."""
import os
import sys
import unittest
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from olx import visitas_parceria as vp  # noqa: E402

M = timezone(timedelta(hours=-4))
S = {"visita_id": 1, "imovel": "Liverpool Reserva Inglesa", "quando": datetime(2026, 10, 22, 14, 0, tzinfo=M),
     "corretor": "Sandersson Ferreira", "dono_nome": "Christian", "dono": "enviado", "dono_respondeu": True,
     "moto": "enviado", "moto_respondeu": False}


class Checklist(unittest.TestCase):
    def test_em_que_pe_esta_e_por_qual_numero(self):
        # Pedro, 30/10: "pôr de qual número fala, e tipo já falei com X, falta falar com ..., e não mandar só uma lista"
        t = vp.checklist({**S, "moto_nome": "Diego"})
        self.assertEqual(t, "📋 Visita agendada: Liverpool Reserva Inglesa, 22/10 (quinta) às 14h00\n"
                            "📱 Estou falando pelo WhatsApp Parceria (92 9445-3618)\n"
                            "✅ Já falei com: Sandersson (corretor, confirmou a visita) e Christian (proprietário, respondeu)\n"
                            "⏳ Mandei mensagem, esperando a resposta: Diego (motoboy)\n"
                            "👉 Agora: esperar a resposta de Diego (motoboy)")
        self.assertNotIn("#", t)

    def test_quem_falta_e_por_que(self):
        t = vp.checklist({**S, "dono": "bloqueado: tel_assumiu", "moto": "sem: a Nay não avisou"})
        self.assertIn("❌ Falta falar com: Christian (proprietário, o Tel tinha assumido a conversa e a mensagem ficou "
                      "parada) e o motoboy (ainda não avisei)", t)
        self.assertIn("👉 Agora: falar com Christian (proprietário) e o motoboy", t)

    def test_todos_avisados(self):
        t = vp.checklist({**S, "moto_respondeu": True})
        self.assertIn("👉 Agora: todos avisados, a visita está combinada", t)
        self.assertNotIn("Falta", t)

    def test_a_assinatura_muda_quando_alguem_responde(self):
        self.assertNotEqual(vp.assinatura(S), vp.assinatura({**S, "moto_respondeu": True}))

    def test_os_avisos(self):
        self.assertIn("o Tel tinha assumido a conversa", vp.aviso_sem_dono({**S, "dono": "bloqueado: tel_assumiu"}))
        self.assertIn("sem telefone no cadastro", vp.aviso_sem_dono({**S, "dono": "sem: sem telefone no cadastro"}))
        self.assertIn("não respondeu em 1 hora", vp.aviso_sem_resposta(S, 60))
        self.assertIn("não entrou no sistema", vp.aviso_sem_visita({"corretor": "X", "imovel": "Y"}))


if __name__ == "__main__":
    unittest.main()
