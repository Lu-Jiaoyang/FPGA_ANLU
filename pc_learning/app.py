"""Native desktop companion. Run from project root: python -m pc_learning.app."""
from pathlib import Path
import tkinter as tk
from tkinter import ttk
from tkinter.scrolledtext import ScrolledText

from PIL import Image, ImageTk
import serial
from serial.tools import list_ports

from .core import LineBuffer, Round, parse_result, search
from .knowledge import ARTICLES, QUESTIONS

ROOT = Path(__file__).resolve().parents[1]
NAVY = "#142c49"
BLUE = "#216b9e"
GREEN = "#14735c"
ORANGE = "#b43e4d"
MUTED = "#61758a"
BG = "#eef3f8"
GOLD = "#edb95e"


class LearningApp:
    def __init__(self, root):
        self.root = root
        self.serial_port = None
        self.buffer = LineBuffer()
        self.round = Round()
        self.search_hits = []
        self.images = {}
        self.poll_id = None
        root.title("FPGA科普互动学习系统 · 太阳系学习助手")
        root.geometry(f"1180x{min(820, root.winfo_screenheight() - 100)}")
        root.minsize(900, 640)
        root.configure(bg=BG)
        root.option_add("*Font", ("Microsoft YaHei UI", 10))
        style = ttk.Style(root)
        style.theme_use("clam")
        style.configure("TFrame", background=BG)
        style.configure("TLabel", background=BG, foreground=NAVY)
        style.configure("Card.TFrame", background="white")
        style.configure("Card.TLabel", background="white", foreground=NAVY)
        style.configure("TButton", padding=(12, 7), background="white", foreground=NAVY,
                        borderwidth=1, bordercolor="#d4e0ec")
        style.map("TButton", background=[("active", "#e5eef7")])
        style.configure("Accent.TButton", background=BLUE, foreground="white", borderwidth=0)
        style.map("Accent.TButton", background=[("active", "#185680")])
        style.configure("TEntry", padding=7, fieldbackground="white", bordercolor="#d4e0ec")
        style.configure("TCombobox", padding=5, fieldbackground="white")
        style.configure("TNotebook", background=BG, borderwidth=0, tabmargins=(0, 0, 0, 8))
        style.configure("TNotebook.Tab", padding=(22, 9), background="#e1eaf3", foreground=MUTED,
                        font=("Microsoft YaHei UI", 10, "bold"))
        style.map("TNotebook.Tab", background=[("selected", "white")], foreground=[("selected", BLUE)])
        style.configure("Treeview", rowheight=27, font=("Microsoft YaHei UI", 10),
                        background="white", fieldbackground="white", borderwidth=0)
        style.configure("Treeview.Heading", background="#e6eef6", foreground=MUTED,
                        padding=(3, 4), font=("Microsoft YaHei UI", 9, "bold"))
        style.map("Treeview", background=[("selected", "#dbeaf6")], foreground=[("selected", NAVY)])

        header = tk.Frame(root, bg=NAVY, padx=24, pady=12)
        header.pack(fill="x")
        orbit = tk.Canvas(header, width=220, height=84, bg=NAVY, highlightthickness=0)
        orbit.pack(side="right", padx=(8, 0))
        for x, y, radius in [(10, 12, 1), (207, 8, 1), (194, 74, 1), (32, 73, 1), (179, 21, 2)]:
            orbit.create_oval(x-radius, y-radius, x+radius, y+radius, fill="#809bb5", outline="")
        for radius in (34, 62, 94):
            orbit.create_oval(110-radius, 42-radius/3, 110+radius, 42+radius/3, outline="#36536e")
        orbit.create_oval(99, 31, 121, 53, fill=GOLD, outline="")
        for x, y, r, color in [(78, 45, 4, "#70bfc8"), (153, 57, 6, "#dc8866"), (199, 32, 8, "#cba987")]:
            orbit.create_oval(x-r, y-r, x+r, y+r, fill=color, outline="")
        tk.Label(header, text="SOLAR SYSTEM   /   太阳系探索", bg=NAVY, fg=GOLD,
                 font=("Microsoft YaHei UI", 9, "bold")).pack(anchor="w")
        tk.Label(header, text="FPGA科普互动学习系统", bg=NAVY, fg="white",
                 font=("Microsoft YaHei UI", 20, "bold")).pack(anchor="w", pady=(3, 0))
        tk.Label(header, text="从观察星球，到理解每一个答案", bg=NAVY, fg="#bdcfe1",
                 font=("Microsoft YaHei UI", 10)).pack(anchor="w", pady=(4, 0))

        connection = ttk.Frame(root, padding=(24, 10))
        connection.pack(fill="x")
        ttk.Label(connection, text="学习设备", font=("Microsoft YaHei UI", 10, "bold")).pack(side="left")
        self.port_name = tk.StringVar()
        self.ports = ttk.Combobox(connection, textvariable=self.port_name, width=10)
        self.ports.pack(side="left", padx=10)
        ttk.Button(connection, text="刷新", command=self.refresh_ports).pack(side="left")
        self.connect_button = ttk.Button(connection, text="连接", style="Accent.TButton", command=self.toggle_connection)
        self.connect_button.pack(side="left", padx=8)
        self.connection_status = ttk.Label(connection, text="●  未连接", foreground=MUTED)
        self.connection_status.pack(side="left", padx=8)

        main = ttk.Frame(root, padding=(24, 0, 24, 0))
        main.pack(fill="both", expand=True)
        main.columnconfigure(1, weight=1)
        main.rowconfigure(0, weight=1)
        sidebar = ttk.Frame(main, width=225, padding=(0, 0, 18, 0))
        sidebar.grid(row=0, column=0, sticky="ns")
        score_card = tk.Frame(sidebar, bg=NAVY, padx=16, pady=8)
        score_card.pack(fill="x")
        tk.Label(score_card, text="我的探索成绩", bg=NAVY, fg="#bdcfe1",
                 font=("Microsoft YaHei UI", 9)).pack(anchor="w")
        self.score_label = tk.Label(score_card, text="— / 100", bg=NAVY, fg=GOLD,
                                    font=("Microsoft YaHei UI", 25, "bold"))
        self.score_label.pack(anchor="w")
        self.progress_label = tk.Label(score_card, text="等待第 1 题结果", bg=NAVY, fg="#d0dfed",
                                       wraplength=190, justify="left", font=("Microsoft YaHei UI", 9))
        self.progress_label.pack(anchor="w")
        ttk.Label(sidebar, text="四站探索", font=("Microsoft YaHei UI", 10, "bold")).pack(anchor="w", pady=(10, 5))
        stations = tk.Frame(sidebar, bg=BG)
        stations.pack(fill="x", pady=(0, 8))
        self.stations = []
        for index, name in enumerate(("太阳", "火星", "木星", "月球"), 1):
            cell = tk.Frame(stations, bg=BG)
            cell.pack(side="left", expand=True, fill="x")
            number = tk.Label(cell, text=str(index), bg="#dfe8f1", fg=MUTED, width=3, pady=0,
                              font=("Microsoft YaHei UI", 10, "bold"))
            number.pack()
            tk.Label(cell, text=name, bg=BG, fg=MUTED, font=("Microsoft YaHei UI", 8)).pack(pady=(2, 0))
            self.stations.append(number)
        ttk.Label(sidebar, text="答题记录", font=("Microsoft YaHei UI", 10, "bold")).pack(anchor="w", pady=(0, 5))
        self.history = ttk.Treeview(sidebar, columns=("q", "selected", "result"), show="headings", height=4,
                                    selectmode="browse")
        for col, title, width in [("q", "题号", 52), ("selected", "选择", 62), ("result", "结果", 79)]:
            self.history.heading(col, text=title)
            self.history.column(col, width=width, anchor="center", stretch=False)
        self.history.tag_configure("correct", foreground=GREEN)
        self.history.tag_configure("wrong", foreground=ORANGE)
        self.history.pack(fill="x")
        self.history.bind("<<TreeviewSelect>>", self.select_history)
        ttk.Button(sidebar, text="清空电脑记录", command=self.clear_records).pack(fill="x", pady=(8, 5))

        self.tabs = ttk.Notebook(main)
        self.tabs.grid(row=0, column=1, sticky="nsew")
        answer_tab = ttk.Frame(self.tabs, padding=16, style="Card.TFrame")
        search_tab = ttk.Frame(self.tabs, padding=16, style="Card.TFrame")
        self.tabs.add(answer_tab, text="答题讲解")
        self.tabs.add(search_tab, text="知识搜索")
        self.result_label = tk.Label(answer_tab, text="等待提交答案 · 探索即将开始", bg="#edf3f9", fg=NAVY,
                                     anchor="w", justify="left", padx=12, pady=10,
                                     font=("Microsoft YaHei UI", 11, "bold"))
        self.result_label.pack(fill="x")
        overview = ttk.Frame(answer_tab, style="Card.TFrame")
        overview.pack(fill="x", pady=12)
        overview.columnconfigure(0, weight=1)
        self.question_label = ttk.Label(overview, text="准备好探索太阳系了吗？", style="Card.TLabel",
                                       wraplength=420, font=("Microsoft YaHei UI", 14, "bold"))
        self.question_label.grid(row=0, column=0, sticky="nw", padx=(0, 12))
        self.options_label = ttk.Label(overview, text="连接学习设备，提交答案后，\n在这里一起寻找星球背后的秘密。",
                                       style="Card.TLabel", wraplength=420, justify="left")
        self.options_label.grid(row=1, column=0, sticky="nw", pady=(10, 0), padx=(0, 12))
        picture = ttk.Frame(overview, width=240, height=180, style="Card.TFrame")
        picture.grid(row=0, column=1, rowspan=2, sticky="ne")
        picture.grid_propagate(False)
        picture.rowconfigure(0, weight=1)
        picture.columnconfigure(0, weight=1)
        self.image_label = tk.Label(picture, text="太阳 · 火星 · 木星 · 月球\n\n提交答案后，点亮你的知识星图", bg="#edf3f9", fg=MUTED,
                                    font=("Microsoft YaHei UI", 10), justify="center")
        self.image_label.grid(sticky="nsew")
        overview.bind("<Configure>", lambda e: self.resize_overview(e.width))
        self.explanation = self.text_area(answer_tab)
        self.set_text(self.explanation, [
            ("每一个答案，都是探索的起点\n\n", "heading"),
            ("在设备上完成选择并提交，这里会同步得分、解析图片和知识讲解。答错也没关系，我们会解释这个选项为什么不合适。\n\n想先了解一点？打开‘知识搜索’，试试太阳、氧化铁、大红斑或月相。", "body"),
        ])

        ttk.Label(search_tab, text="星球知识库", style="Card.TLabel",
                  font=("Microsoft YaHei UI", 16, "bold")).pack(anchor="w")
        ttk.Label(search_tab, text="从一个好奇的问题开始：太阳为什么发光？火星为什么是红色？",
                  style="Card.TLabel", foreground=MUTED, wraplength=550).pack(anchor="w", pady=(5, 12))
        search_row = ttk.Frame(search_tab, style="Card.TFrame")
        search_row.pack(fill="x")
        self.query = tk.StringVar()
        entry = ttk.Entry(search_row, textvariable=self.query)
        entry.pack(side="left", fill="x", expand=True)
        entry.bind("<Return>", lambda event: self.run_search())
        ttk.Button(search_row, text="搜索知识", style="Accent.TButton", command=self.run_search).pack(side="left", padx=(8, 0))
        self.search_status = ttk.Label(search_tab, text="", style="Card.TLabel", foreground=MUTED)
        self.search_status.pack(anchor="w", pady=(10, 5))
        self.search_list = tk.Listbox(search_tab, height=3, activestyle="none", exportselection=False,
                                     relief="flat", highlightthickness=1, highlightbackground="#d4e0ec",
                                     bg="#f5f8fc", fg=NAVY, selectbackground="#dbeaf6", selectforeground=NAVY,
                                     font=("Microsoft YaHei UI", 11))
        self.search_list.pack(fill="x", pady=(0, 12))
        self.search_list.bind("<<ListboxSelect>>", self.show_article)
        self.article_text = self.text_area(search_tab)
        self.notice = tk.StringVar(value="选择设备串口并连接，再在设备上开始答题。知识搜索无需连接即可使用。")
        footer = ttk.Label(root, textvariable=self.notice, foreground=MUTED, padding=(24, 9), wraplength=1100,
                           font=("Microsoft YaHei UI", 9))
        footer.pack(side="bottom", fill="x", before=main)
        root.bind("<Configure>", lambda e: footer.configure(wraplength=max(500, e.width - 48)) if e.widget == root else None)
        self.refresh_ports()
        self.run_search()
        root.protocol("WM_DELETE_WINDOW", self.close)
        self.poll_id = root.after(50, self.poll_serial)

    @staticmethod
    def text_area(parent):
        widget = ScrolledText(parent, wrap="word", relief="flat", borderwidth=0, padx=4, pady=8,
                              bg="white", fg=NAVY, height=8, spacing1=2, spacing3=4,
                              font=("Microsoft YaHei UI", 11), cursor="arrow")
        widget.tag_configure("heading", font=("Microsoft YaHei UI", 12, "bold"), foreground=BLUE)
        widget.tag_configure("body", font=("Microsoft YaHei UI", 11))
        widget.pack(fill="both", expand=True)
        return widget

    @staticmethod
    def set_text(widget, chunks):
        widget.configure(state="normal")
        widget.delete("1.0", "end")
        for text, tag in chunks:
            widget.insert("end", text, tag)
        widget.configure(state="disabled")
        widget.yview_moveto(0)

    def resize_overview(self, width):
        for label in (self.question_label, self.options_label):
            label.configure(wraplength=max(120, width - 260))
        self.result_label.configure(wraplength=max(240, width - 24))

    def refresh_ports(self):
        if self.serial_port:
            return
        available = list(list_ports.comports())
        names = [port.device for port in available]
        self.ports.configure(values=names)
        if self.port_name.get() not in names:
            preferred = next((p.device for p in available if p.vid == 0x1A86), None)
            if names:
                self.port_name.set(preferred or names[0])

    def toggle_connection(self):
        if self.serial_port:
            self.disconnect("已断开连接，电脑记录保留。")
            return
        port = self.port_name.get().strip()
        candidate = serial.Serial(port=None, baudrate=115200, timeout=0, write_timeout=0)
        candidate.dtr = False
        candidate.rts = False
        try:
            candidate.port = port
            candidate.open()
        except (serial.SerialException, OSError, ValueError) as exc:
            candidate.close()
            self.connection_status.configure(text="连接失败", foreground=ORANGE)
            self.notice.set(f"无法打开 {port}：请关闭旧串口窗口，核对端口及 USB 数据线。{exc}")
            return
        self.serial_port = candidate
        self.buffer = LineBuffer()
        self.ports.configure(state="disabled")
        self.connect_button.configure(text="断开")
        self.connection_status.configure(text=f"●  已连接 {port} · 等待答题", foreground=GREEN)
        self.notice.set("连接成功。在设备知识浏览界面短按 KEY3 开始答题，KEY4 提交后自动显示讲解。")

    def disconnect(self, message):
        if self.serial_port:
            try:
                self.serial_port.close()
            except (serial.SerialException, OSError):
                pass
        self.serial_port = None
        self.buffer = LineBuffer()
        self.ports.configure(state="normal")
        self.connect_button.configure(text="连接")
        self.connection_status.configure(text="●  未连接", foreground=MUTED)
        self.notice.set(message)

    def poll_serial(self):
        try:
            if self.serial_port:
                count = min(self.serial_port.in_waiting, 4096)
                if count:
                    self.receive_bytes(self.serial_port.read(count))
        except (serial.SerialException, OSError) as exc:
            self.disconnect(f"串口连接已中断，记录保留。检查数据线后重新连接。{exc}")
        self.poll_id = self.root.after(50, self.poll_serial)

    def receive_bytes(self, data):
        for line in self.buffer.feed(data):
            try:
                result = parse_result(line)
                action = self.round.accept(result)
            except ValueError as exc:
                self.notice.set(f"已忽略异常消息：{exc}。")
                continue
            if action == "duplicate":
                self.notice.set("已忽略重复结果，得分未重复计算。")
                continue
            if action == "new":
                self.history.delete(*self.history.get_children())
            key = str(result.question)
            self.history.insert("", "end", iid=key, values=(result.question, result.selected,
                                "答对" if result.correct else "答错"), tags=("correct" if result.correct else "wrong",))
            self.history.selection_set(key)
            self.history.focus(key)
            self.score_label.configure(text=f"{result.score} / 100")
            count = len(self.round.results)
            progress = "本轮四题已收齐" if count == 4 else f"已接收 {count} / 4 题"
            self.progress_label.configure(text=progress)
            self.update_stations()
            self.show_result(result.question)
            self.tabs.select(0)
            self.notice.set(f"已收到第 {result.question} 题结果。" +
                            ("部分记录缺失，得分以设备为准。" if count != result.question else "") +
                            ("四题完成，可以点击记录回顾。" if count == 4 else "可查看解析，或搜索相关知识。"))

    def update_stations(self):
        for number, label in enumerate(self.stations, 1):
            result = self.round.results.get(number)
            label.configure(bg=("#d9efe4" if result.correct else "#f8e0e5") if result else "#dfe8f1",
                            fg=(GREEN if result.correct else ORANGE) if result else MUTED)

    def select_history(self, event=None):
        selected = self.history.selection()
        if selected:
            self.show_result(int(selected[0]))

    def show_result(self, number):
        result = self.round.results[number]
        question = QUESTIONS[number]
        self.result_label.configure(text=f"第 {number} 题 · {'答对了！' if result.correct else '再理解一下这道题'}  "
                                   f"你的选择 {result.selected}  /  正确答案 {result.answer}",
                                   bg="#e8f5ef" if result.correct else "#fceef0", fg=GREEN if result.correct else ORANGE)
        self.question_label.configure(text=question["question"])
        self.options_label.configure(text="\n".join(f"{key}  {value}" for key, value in question["options"].items()))
        if number not in self.images:
            try:
                with Image.open(ROOT / "grouped_resolution_assets" / question["image"]) as source:
                    preview = source.convert("RGB").resize((240, 180), Image.Resampling.LANCZOS)
                self.images[number] = ImageTk.PhotoImage(preview, master=self.root)
            except OSError:
                self.images[number] = None
        photo = self.images[number]
        self.image_label.configure(image=photo if photo else "", text="解析图片暂不可用" if not photo else "")
        chunks = [("为什么是这个答案\n", "heading"), (question["explanation"] + "\n\n", "body")]
        if not result.correct:
            chunks += [(f"你选择的 {result.selected} 为什么不对\n", "heading"),
                       (question["mistakes"][result.selected] + "\n\n", "body")]
        chunks += [("再了解一点\n", "heading"), (question["further"] + "\n\n", "body"),
                   ("继续探索\n", "heading"), (f"在“知识搜索”中输入“{question['topic']}”，阅读相关知识。", "body")]
        self.set_text(self.explanation, chunks)

    def clear_records(self):
        self.round = Round()
        self.history.delete(*self.history.get_children())
        self.score_label.configure(text="— / 100")
        self.progress_label.configure(text="电脑记录已清空")
        self.update_stations()
        self.result_label.configure(text="等待提交答案 · 探索即将开始", bg="#edf3f9", fg=NAVY)
        self.question_label.configure(text="等待新的答题结果")
        self.options_label.configure(text="此操作只清空电脑记录，不会复位学习设备。")
        self.image_label.configure(image="", text="收到结果后显示解析图")
        self.set_text(self.explanation, [("开始新一轮：按设备 KEY1 复位，浏览知识后短按 KEY3 开始答题，用 KEY4 提交答案。请保持本窗口已连接。", "body")])
        self.notice.set("仅清空了电脑记录；设备状态及得分未改变。")

    def run_search(self):
        self.search_hits = search(self.query.get())
        self.search_list.delete(0, "end")
        for article in self.search_hits:
            self.search_list.insert("end", article["title"])
        self.search_status.configure(text=f"找到 {len(self.search_hits)} 条 · 本地共 {len(ARTICLES)} 条知识")
        if self.search_hits:
            self.search_list.selection_set(0)
            self.show_article()
        else:
            self.set_text(self.article_text, [("暂时没有找到相关内容\n\n", "heading"),
                          ("试试更短的关键词，例如“月亮”“火星”“氧化铁”或“大红斑”。这里查询的是内置知识库。", "body")])

    def show_article(self, event=None):
        selected = self.search_list.curselection()
        if selected:
            article = self.search_hits[selected[0]]
            self.set_text(self.article_text, [(article["title"] + "\n", "heading"), (article["body"], "body")])

    def close(self):
        if self.poll_id:
            self.root.after_cancel(self.poll_id)
        self.disconnect("窗口已关闭。")
        self.root.destroy()


def main():
    root = tk.Tk()
    LearningApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
