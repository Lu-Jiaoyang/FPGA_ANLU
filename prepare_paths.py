"""将 TD 工程、ROM 和仿真脚本路径迁移到当前解压目录。"""
from pathlib import Path
import argparse
import re
from xml.etree import ElementTree as ET


def prepare(root, td=None, modelsim=None):
    project = root/'fpga/src/td_project/single_board_quiz.al'
    old_project = re.search(r'<Project\b[^>]*\bPath="([^"]+)"', project.read_text(encoding='utf-8')).group(1)
    suffix = '/fpga/src/td_project'
    if not old_project.endswith(suffix):
        raise ValueError('无法识别工程根目录')
    old_root = old_project[:-len(suffix)]
    tool_root = 'D:/Anlogic/TD_Release_2026.1_SP2'
    if td:
        td = Path(td).resolve()
        if not (td/'scripts/DefaultFlow.tcl').is_file():
            raise ValueError('TD 目录中缺少 scripts/DefaultFlow.tcl')
    if modelsim:
        modelsim = Path(modelsim).resolve()
        if not (modelsim/'modelsim.ini').is_file():
            raise ValueError('ModelSim 目录中缺少 modelsim.ini')
    changed = 0
    for p in root.rglob('*'):
        if not p.is_file() or p.suffix.lower() not in {'.v','.vh','.sv','.vhd','.tcl','.do','.al','.prj','.cfg','.ipc'}:
            continue
        raw = p.read_bytes()
        try:
            before = raw.decode('utf-8')
        except UnicodeDecodeError:
            continue
        after = before.replace(old_root, root.as_posix())
        if td:
            after = after.replace(tool_root, td.as_posix())
        if after != before:
            p.write_bytes(after.encode('utf-8'))
            changed += 1
    if modelsim:
        (root/'modelsim.ini').write_text('[Library]\nothers = '+(modelsim/'modelsim.ini').as_posix()+'\n',encoding='utf-8')
    for extension in ('.al','.prj'):
        p=project.with_suffix(extension)
        tree=ET.fromstring(p.read_text(encoding='utf-8').replace('UsedInP&R','UsedInPandR'))
        refs=[(p.parent/x.attrib['Path']).resolve() for x in tree.iter('File')]
        if len(refs)!=66 or any(not x.is_relative_to(root) or not x.is_file() for x in refs):
            raise ValueError('工程文件引用检查失败：'+extension)
    for name in ('answer_audio.dath','boot_pic01.dath'):
        target=root/'fpga/src/user_source/hdl_source'/name
        if not target.is_file():
            raise ValueError('ROM 初始化文件缺失：'+name)
    print(f'路径准备完成，更新 {changed} 个文件；两个工程文件各 66 项引用检查通过。')


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--td',help='TD 安装根目录，可省略以保留脚本内的安装路径')
    parser.add_argument('--modelsim',help='含 modelsim.ini 的 ModelSim 安装目录')
    args=parser.parse_args()
    prepare(Path(__file__).resolve().parent,args.td,args.modelsim)
