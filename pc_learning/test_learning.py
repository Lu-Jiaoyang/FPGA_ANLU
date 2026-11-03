import unittest
import sys
from unittest.mock import patch

from .core import LineBuffer, Round, parse_result, search
from .knowledge import QUESTIONS

SAMPLE = [
    b"Q=1,SEL=D,ANS=B,OK=0,SCORE=000\r\n",
    b"Q=2,SEL=A,ANS=C,OK=0,SCORE=000\r\n",
    b"Q=3,SEL=A,ANS=A,OK=1,SCORE=025\r\n",
    b"Q=4,SEL=A,ANS=D,OK=0,SCORE=025\r\n",
]


class CoreTests(unittest.TestCase):
    def test_actual_hardware_transcript(self):
        game = Round()
        for line in SAMPLE:
            game.accept(parse_result(line))
        self.assertEqual(len(game.results), 4)
        self.assertEqual(game.results[4].score, 25)
        self.assertEqual([q for q, r in game.results.items() if r.correct], [3])

    def test_every_answer_pattern(self):
        for mask in range(16):
            game, score = Round(), 0
            for q, question in QUESTIONS.items():
                correct = bool(mask & (1 << (q - 1)))
                answer = question["answer"]
                selected = answer if correct else next(k for k in "ABCD" if k != answer)
                score += 25 if correct else 0
                line = f"Q={q},SEL={selected},ANS={answer},OK={int(correct)},SCORE={score:03d}\r\n".encode()
                game.accept(parse_result(line))
            self.assertEqual(game.results[4].score, 25 * mask.bit_count())

    def test_reject_malformed_or_inconsistent(self):
        bad = [b"", SAMPLE[0][:-1], b"noise" + SAMPLE[0], SAMPLE[0] + b"x",
               SAMPLE[0].replace(b"Q=1", b"Q=5"), SAMPLE[0].replace(b"SEL=D", b"SEL=E"),
               SAMPLE[0].replace(b"ANS=B", b"ANS=A"), SAMPLE[0].replace(b"OK=0", b"OK=1"),
               SAMPLE[0].replace(b"000", b"025"), SAMPLE[0].replace(b"000", b"999"),
               SAMPLE[2].replace(b"025", b"000"), SAMPLE[2].replace(b"025", b"024"),
               SAMPLE[0].replace(b"D", b"\xff"), SAMPLE[0] * 2]
        for line in bad:
            with self.subTest(line=line), self.assertRaises(ValueError):
                parse_result(line)

    def test_every_fragment_boundary(self):
        transcript = b"".join(SAMPLE)
        for split in range(len(transcript) + 1):
            buffer = LineBuffer()
            self.assertEqual(buffer.feed(transcript[:split]) + buffer.feed(transcript[split:]), SAMPLE)
        buffer, lines = LineBuffer(), []
        for byte in transcript:
            lines += buffer.feed(bytes([byte]))
        self.assertEqual(lines, SAMPLE)

    def test_oversize_noise_recovers_at_line_boundary(self):
        buffer = LineBuffer()
        self.assertEqual(buffer.feed(b"x" * 100000), [])
        self.assertLessEqual(len(buffer.pending), 128)
        self.assertEqual(buffer.feed(b"tail\n" + SAMPLE[0]), [SAMPLE[0]])

    def test_duplicate_restart_and_missing_records(self):
        game = Round()
        game.accept(parse_result(SAMPLE[1]))
        self.assertEqual(game.accept(parse_result(SAMPLE[1])), "duplicate")
        game.accept(parse_result(SAMPLE[3]))
        self.assertEqual(len(game.results), 2)
        with self.assertRaises(ValueError):
            game.accept(parse_result(SAMPLE[2]))
        self.assertEqual(game.accept(parse_result(SAMPLE[0])), "new")
        self.assertEqual(list(game.results), [1])

    def test_score_jump_does_not_corrupt_history(self):
        game = Round()
        game.accept(parse_result(SAMPLE[0]))
        with self.assertRaises(ValueError):
            game.accept(parse_result(SAMPLE[1].replace(b"000", b"025")))
        self.assertEqual(list(game.results), [1])

    def test_search_alias_multiword_and_no_match(self):
        self.assertIn("月亮", search("月亮")[0]["title"])
        self.assertTrue(search("木星 风暴"))
        self.assertTrue(search("SUN"))
        self.assertEqual(search("量子计算"), [])
        self.assertEqual(len(search("   ")), 8)
        self.assertTrue(search("氧化铁"))


class FakeSerial:
    def __init__(self, **kwargs):
        self.port = kwargs.get("port")
        self.is_open = False
        self.data = bytearray()
        self.dtr = self.rts = True

    def open(self):
        self.is_open = True

    def close(self):
        self.is_open = False

    @property
    def in_waiting(self):
        return len(self.data)

    def read(self, count):
        chunk = bytes(self.data[:count])
        del self.data[:count]
        return chunk


class WindowTests(unittest.TestCase):
    def setUp(self):
        import tkinter as tk
        from .app import LearningApp
        self.root = tk.Tk()
        self.root.withdraw()
        with patch("pc_learning.app.list_ports.comports", return_value=[]):
            self.app = LearningApp(self.root)
        self.root.after_cancel(self.app.poll_id)
        self.app.poll_id = None
        self.app.port_name.set("COM_TEST")

    def tearDown(self):
        self.app.close()

    def test_real_messages_render_and_history_can_be_revisited(self):
        self.app.receive_bytes(b"".join(SAMPLE))
        self.root.update_idletasks()
        self.assertEqual(self.app.score_label.cget("text"), "25 / 100")
        self.assertEqual(len(self.app.history.get_children()), 4)
        self.assertIn("月光", self.app.question_label.cget("text"))
        detail = self.app.explanation.get("1.0", "end")
        self.assertIn("你选择的 A 为什么不对", detail)
        self.assertIn("反射", detail)
        self.assertEqual(len(self.app.images), 4)
        self.assertTrue(all(self.app.images.values()))
        self.app.show_result(3)
        self.assertIn("答对了", self.app.result_label.cget("text"))
        self.assertNotIn("为什么不对", self.app.explanation.get("1.0", "end"))
        self.app.receive_bytes(SAMPLE[0])
        self.assertEqual(len(self.app.history.get_children()), 1)
        self.assertEqual(self.app.score_label.cget("text"), "0 / 100")

    def test_fragmented_transport_disconnect_and_reconnect(self):
        with patch("pc_learning.app.serial.Serial", FakeSerial):
            self.app.toggle_connection()
            port = self.app.serial_port
            self.assertTrue(port.is_open)
            self.assertFalse(port.dtr or port.rts)
            port.data += SAMPLE[0][:12]
            self.app.poll_serial()
            self.root.after_cancel(self.app.poll_id)
            self.assertFalse(self.app.round.results)
            port.data += SAMPLE[0][12:]
            self.app.poll_serial()
            self.root.after_cancel(self.app.poll_id)
            self.assertEqual(len(self.app.round.results), 1)
            self.app.receive_bytes(b"partial")
            self.app.toggle_connection()
            self.assertFalse(port.is_open)
            self.app.toggle_connection()
            self.assertFalse(self.app.buffer.pending)
            self.assertEqual(len(self.app.round.results), 1)

    def test_invalid_line_and_port_failure(self):
        import serial
        self.app.receive_bytes(b"bad\r\n" + SAMPLE[0])
        self.app.receive_bytes(SAMPLE[0].replace(b"OK=0", b"OK=1"))
        self.assertEqual(len(self.app.round.results), 1)
        self.assertIn("异常", self.app.notice.get())
        with patch.object(FakeSerial, "open", side_effect=serial.SerialException("Access denied")), \
             patch("pc_learning.app.serial.Serial", FakeSerial):
            self.app.toggle_connection()
        self.assertIsNone(self.app.serial_port)
        self.assertIn("关闭旧串口", self.app.notice.get())

    def test_search_and_local_clear(self):
        self.app.query.set("月相")
        self.app.run_search()
        self.assertIn("地球的影子", self.app.article_text.get("1.0", "end"))
        self.app.query.set("不存在的关键词")
        self.app.run_search()
        self.assertEqual(self.app.search_list.size(), 0)
        self.assertIn("暂时没有找到", self.app.article_text.get("1.0", "end"))
        self.app.receive_bytes(b"".join(SAMPLE))
        self.app.clear_records()
        self.assertFalse(self.app.round.results)
        self.assertFalse(self.app.history.get_children())

    def test_single_device_guidance_and_real_progress(self):
        def visible_text(widget):
            text = []
            if "text" in widget.keys():
                text.append(str(widget.cget("text")))
            for child in widget.winfo_children():
                text.extend(visible_text(child))
            return text

        def check_wording():
            content = "\n".join(visible_text(self.root) + [self.root.title(), self.app.notice.get(),
                                self.app.explanation.get("1.0", "end")])
            self.assertIn("FPGA科普互动学习系统", content)

        check_wording()
        with patch("pc_learning.app.serial.Serial", FakeSerial):
            self.app.toggle_connection()
        self.assertIn("KEY3", self.app.notice.get())
        check_wording()
        self.app.receive_bytes(b"".join(SAMPLE))
        self.assertEqual(self.app.stations[0].cget("bg"), "#f8e0e5")
        self.assertEqual(self.app.stations[2].cget("bg"), "#d9efe4")
        check_wording()
        self.app.receive_bytes(SAMPLE[0])
        self.assertEqual(self.app.stations[2].cget("bg"), "#dfe8f1")
        self.app.clear_records()
        self.assertTrue(all(label.cget("bg") == "#dfe8f1" for label in self.app.stations))
        self.assertIn("KEY1", self.app.explanation.get("1.0", "end"))
        check_wording()

    def test_unplug_keeps_results_and_allows_reconnect(self):
        self.app.receive_bytes(SAMPLE[0])
        with patch("pc_learning.app.serial.Serial", FakeSerial):
            self.app.toggle_connection()
            port = self.app.serial_port
            with patch.object(FakeSerial, "in_waiting", new_callable=unittest.mock.PropertyMock,
                              side_effect=OSError("USB removed")):
                self.app.poll_serial()
            self.root.after_cancel(self.app.poll_id)
            self.assertFalse(port.is_open)
            self.assertIsNone(self.app.serial_port)
            self.assertEqual(len(self.app.round.results), 1)
            self.assertIn("中断", self.app.notice.get())
            self.app.toggle_connection()
            self.assertTrue(self.app.serial_port.is_open)

    def test_late_connection_keeps_missing_questions_unknown(self):
        self.app.receive_bytes(SAMPLE[2])
        self.assertEqual(self.app.score_label.cget("text"), "25 / 100")
        self.assertEqual(self.app.stations[0].cget("bg"), "#dfe8f1")
        self.assertEqual(self.app.stations[2].cget("bg"), "#d9efe4")
        self.assertIn("记录缺失", self.app.notice.get())


if __name__ == "__main__":
    unittest.main(testRunner=unittest.TextTestRunner(stream=sys.stdout, verbosity=2))
