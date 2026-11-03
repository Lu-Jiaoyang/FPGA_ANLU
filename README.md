# FPGA科普互动学习系统

基于 EG4S20BG256 的单颗 FPGA 离线互动学习工程。实时图像、声音、答题、计分和反馈由 RTL 实现；电脑程序用于接收答题记录和本地知识检索，不参与计分。

## 工程内容

| 目录或文件 | 用途 |
|---|---|
| `fpga/src/td_project/single_board_quiz.al` | Tang Dynasty 工程入口 |
| `fpga/src/user_source/hdl_source/top_tf_hdmi_audio.v` | RTL 顶层，模块名 `top` |
| `common/`、`interaction/rtl/` | 片内交互控制、计分、显示与串口上报 |
| `sim/`、`test_*.do` | 测试台、参考数据及 ModelSim 脚本 |
| `pc_learning/`、`open_learning_app.cmd` | 太阳系主题电脑学习窗口 |
| `grouped_resolution_assets/` | TF 卡使用的十二张 BMP 图片 |
| `audio_assets/` | 反馈录音预览、素材来源与许可 |
| `reports/` | 当前实现资源、时序、仿真与 Flash 校验结果 |
| `single_board_quiz.bit` | 已通过上板检查及 Flash 校验的配置文件 |

## 使用和重建

1. 解压到英文目录，保留完整目录结构。安装 Python 后，在根目录执行 `python prepare_paths.py`，迁移工程和 ROM 路径。若工具安装位置不同，执行 `python prepare_paths.py --td "D:/Anlogic/TD_Release_2026.1_SP2" --modelsim "D:/EDA/ModelSim10.6e"`，替换为实际目录。
2. 使用 Tang Dynasty Release_2026.1_SP2 打开 `.al` 工程。目标器件 EG4S20BG256；引脚和时序约束位于 `fpga/src/user_source/constraints_source/`。完整综合、布局布线后生成配置文件；也可在 TD 命令行环境执行根目录 `build.tcl`。
3. 仿真使用 ModelSim SE-64 10.6e，在工程根目录执行例如 `vsim -c -do test_single_board.do`。八组提交验证脚本为 `single_board`、`audio_volume`、`learning_media`、`center_menu`、`sdram_clock_refresh`、`sdram_bandwidth`、`presentation`、`fat32_resize`，均带 `test_` 前缀和 `.do` 后缀。厂商 PLL、BRAM 模型来自 TD 的 `sim_release/eg4`。
4. 电脑程序依赖见 `requirements.txt`：`python -m pip install -r requirements.txt`，再双击启动脚本，或运行 `python -m pc_learning.app`。自动测试命令为 `python -m unittest pc_learning.test_learning -v`。串口采用 115200 / 8N1。
5. TF 卡使用 FAT32，将十二个 `PIC01.BMP`～`PIC12.BMP` 复制至根目录。四张知识图为 640×480，四张题图为 800×600，四张解析为 1024×768。素材为 24 位无压缩 BMP；HDMI 输出固定为 640×480。换卡、接线时先断电。
6. 使用 BitWriter 下载根目录 bit；Flash 使用匹配板卡的配置方式。当前交付文件已在目标设备完成 Flash 写入、随写校验和独立校验，详见 `reports/flash_verification.json`。

## 按键和参数

| 场景 | KEY2 | KEY3 | KEY4 |
|---|---|---|---|
| 知识浏览 | 下一张知识图 | 短按开始答题；长按约 1 秒进入菜单 | 开始／停止知识轮播 |
| 参数菜单 | 减小参数 | 短按切换菜单项；长按退出 | 增大参数 |
| 答题 | 下一选项 | 上一选项 | 提交；解析后进入下一题 |
| 结算 | 切换数码管／灯效逻辑输出 | 按当前状态处理 | 错题回顾；继续按键翻阅 |

KEY1 统一复位。亮度和对比度 0～200%，步长 25%，默认 100%；轮播周期 3／5／10／15 秒；音量 0／25／50／75／100%。左上角常显参数，中央菜单显示中文调节项；分辨率是当前原图尺寸，仅显示。设置不掉电保存。

数码管与 LED6～13 存在硬件复用，需配合物理 SW6 切换。LED1～4 记录四道题的正误；结算灯效为同步呼吸。答错后保留原始串口上报，同时显示正确选项和解析；每题 25 分。结算后可回顾错题且不重复计分。

## 实现与验证

SDRAM 控制和器件时钟均为 50 MHz，器件时钟延后 7 ns；刷新请求间隔 31.24 μs。控制域 100 MHz、视频域 25 MHz、HDMI 串化时钟 125 MHz。布局布线报告最差 Setup +0.154 ns、Hold +0.011 ns，总负裕量均为 0，覆盖率 99.99%。结论限于现有约束覆盖路径；外部 I/O 延迟和完整 CDC 审计未包含在该结论中。

| 资源 | 使用量／总量 | 占用率 |
|---|---|---|
| LUT | 14476／19600 | 73.86% |
| REG | 8944／19600 | 45.63% |
| BRAM9K | 53／64 | 82.81% |
| BRAM32K | 13／16 | 81.25% |
| DSP | 13／29 | 44.83% |
| PLL | 3／4 | 75.00% |

八组 RTL 验证及十五项电脑测试通过。图像验证包括逐像素独立参考值比较；SDRAM 吞吐测试验证控制、FIFO 与刷新调度，未建模 DQ 存储数据。音柱表示 PCM 幅度与短时历史，屏幕不显示频谱。缩放采用最近邻，并对精确二倍缩小使用 2×2 均值；最大输入 1920×1080，输出为 4:3，当前素材均为 4:3。电脑知识检索为本地固定知识库。

`SHA256SUMS.txt` 校验解压原始文件；执行路径迁移或仿真后部分文本及输出文件会变化。配置文件 SHA-256 为 `77b208772004bcc688503cac73cc5403d7888d0846a4e15edf62d9e323dd3379`。交付不包含开发日志、备份或编译缓存。当前程序已获实板功能确认；此次 Flash 编程后尚未进行物理断电重启及定量长时间可靠性测试。
