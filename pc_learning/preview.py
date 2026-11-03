"""Visual check with recorded sample data; never opens a serial port."""
from pathlib import Path
import tkinter as tk
from unittest.mock import patch
from PIL import ImageGrab

from .app import LearningApp
from .test_learning import SAMPLE


def main():
    root = tk.Tk()
    with patch("pc_learning.app.list_ports.comports", return_value=[]):
        app = LearningApp(root)
    root.title("界面检查 · 记录回放（非实时串口）")
    root.geometry("1180x820+20+20")
    root.attributes("-topmost", True)
    root.lift()
    app.notice.set("界面测试：回放用户提供的四条消息，未连接串口。")
    output = Path(__file__).resolve().parent / "previews"
    output.mkdir(exist_ok=True)
    failure = []

    def capture(name):
        root.update_idletasks()
        sidebar = app.score_label.master.master
        for widget in sidebar.winfo_children():
            assert widget.winfo_ismapped(), f"Hidden sidebar widget: {widget}"
            assert widget.winfo_y() + widget.winfo_height() <= sidebar.winfo_height(), str(widget)
        assert app.explanation.winfo_height() >= 60
        x, y = root.winfo_rootx(), root.winfo_rooty()
        screen = ImageGrab.grab()
        sx, sy = screen.width / root.winfo_screenwidth(), screen.height / root.winfo_screenheight()
        box = (round(x * sx), round(y * sy), round((x + root.winfo_width()) * sx),
               round((y + root.winfo_height()) * sy))
        screen.crop(box).save(output / name)

    def search_screen():
        try:
            capture("answer.png")
            app.history.selection_set("3")
            app.show_result(3)
            root.after(300, correct_screen)
        except Exception as exc:
            failure.append(exc); app.close()

    def correct_screen():
        try:
            capture("correct.png")
            app.tabs.select(1)
            app.query.set("月相")
            app.run_search()
            root.after(600, compact_screen)
        except Exception as exc:
            failure.append(exc); app.close()

    def compact_screen():
        try:
            capture("search.png")
            app.tabs.select(0)
            app.history.selection_set("1")
            app.show_result(1)
            root.geometry("900x640+20+20")
            root.after(600, finish)
        except Exception as exc:
            failure.append(exc); app.close()

    def finish():
        try:
            capture("compact.png")
            app.tabs.select(1)
            root.after(300, compact_search)
        except Exception as exc:
            failure.append(exc); app.close()

    def compact_search():
        try:
            capture("compact_search.png")
        except Exception as exc:
            failure.append(exc)
        finally:
            app.close()

    def initial_screen():
        try:
            capture("initial.png")
            app.receive_bytes(b"".join(SAMPLE))
            app.notice.set("界面测试：回放用户提供的四条消息，未连接串口。")
            root.after(400, search_screen)
        except Exception as exc:
            failure.append(exc); app.close()

    root.after(800, initial_screen)
    root.mainloop()
    if failure:
        raise failure[0]
    print("Saved initial/answer/correct/search/compact/compact_search captures; layout checks passed:", output)


if __name__ == "__main__":
    main()
