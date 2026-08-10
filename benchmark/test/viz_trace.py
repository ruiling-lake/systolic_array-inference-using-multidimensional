#!/usr/bin/env python3
"""把 tiny-gpu 的执行 trace 日志可视化成流水线状态泳道图。

用法:
    python3 test/viz_trace.py [log文件] [--start N] [--end N] [--no-show] [--out 输出.png]
默认读取 test/logs 下最新的日志, 输出 test/logs/<日志名>.png
"""
import argparse
import glob
import os
import re
import sys

import matplotlib.pyplot as plt
from matplotlib.patches import Patch
from matplotlib import font_manager

for f in font_manager.findSystemFonts(fontpaths=["/usr/share/fonts/opentype/noto"]):
    if "CJK" in f:
        font_manager.fontManager.addfont(f)
plt.rcParams["font.sans-serif"] = ["Noto Sans CJK JP", "DejaVu Sans"]
plt.rcParams["axes.unicode_minus"] = False

STATE_COLORS = {
    "IDLE": "#ECEFF1", "FETCH": "#42A5F5", "DECODE": "#26C6DA",
    "REQUEST": "#FFA726", "WAIT": "#EF5350", "EXECUTE": "#66BB6A",
    "UPDATE": "#AB47BC", "DONE": "#455A64",
}
LSU_COLORS = {
    "IDLE": "#ECEFF1", "REQUESTING": "#FFA726",
    "WAITING": "#EF5350", "DONE": "#66BB6A",
}

RE_CYCLE = re.compile(r"Cycle\s+(\d+)")
RE_CORE = re.compile(r"\+[- ]*Core (\d+)[ -]*\+")
RE_THREAD = re.compile(r"\+[- ]*Thread (\d+)[ -]*\+")


def parse_log(log_path):
    """解析日志, 返回每 (cycle, core, thread) 的状态快照。"""
    data = {}  # (cycle, core, thread) -> dict
    cycle = core = thread = None
    entry = None

    def commit():
        if entry is not None and cycle is not None and core is not None and thread is not None:
            data[(cycle, core, thread)] = entry

    with open(log_path, "r") as f:
        for raw in f:
            line = raw.strip()
            m = RE_CYCLE.search(line)
            if m:
                commit()
                cycle = int(m.group(1)); core = thread = None; entry = None
                continue
            m = RE_CORE.search(line)
            if m and ("Core" in line and "State" not in line):
                commit()
                core = int(m.group(1)); thread = None; entry = None
                continue
            m = RE_THREAD.search(line)
            if m and ("Thread" in line):
                commit()
                thread = int(m.group(1))
                entry = {"pc": None, "instr": None, "core": None,
                         "lsu": None, "fetcher": None}
                continue
            if entry is None or cycle is None:
                continue
            if line.startswith("PC:"):
                entry["pc"] = int(re.sub(r"\D", "", line))
            elif line.startswith("Instruction:"):
                entry["instr"] = line.split(":", 1)[1].strip()
            elif line.startswith("Core State:"):
                entry["core"] = line.split(":", 1)[1].strip()
            elif line.startswith("LSU State:"):
                entry["lsu"] = line.split(":", 1)[1].strip()
            elif line.startswith("Fetcher State:"):
                entry["fetcher"] = line.split(":", 1)[1].strip()
    commit()

    if not data:
        sys.exit("没有解析到任何周期数据, 请确认日志格式")

    lanes = sorted({(c, t) for (_cyc, c, t) in data}, key=lambda x: (x[0], x[1]))
    return data, lanes


def build_runs(data, lanes, state_key):
    """对每条 lane, 把连续相同的状态压缩成 (start, end, state) 段。"""
    runs = {}
    for lane in lanes:
        samples = sorted(
            ((k[0], v[state_key]) for k, v in data.items()
             if k[1] == lane[0] and k[2] == lane[1] and v[state_key]),
            key=lambda x: x[0])
        seg = []
        for cyc, st in samples:
            if seg and seg[-1][2] == st and seg[-1][1] == cyc - 1:
                seg[-1][1] = cyc
            else:
                seg.append([cyc, cyc, st])
        runs[lane] = [(s, e - s + 1, st) for s, e, st in seg]
    return runs


def draw_band(ax, lanes, runs, colors, ylabels, xrange):
    handles = {}
    lane_y = {lane: i for i, lane in enumerate(lanes)}
    for lane, segs in runs.items():
        y = lane_y[lane]
        for s, w, st in segs:
            color = colors.get(st, "#FFFFFF")
            ax.broken_barh([(s, w)], (y - 0.4, 0.8), facecolors=color, edgecolors="#FFFFFF", linewidth=0.5)
            handles.setdefault(st, Patch(facecolor=color, edgecolor="grey", label=st))
    ax.set_yticks(range(len(lanes)))
    ax.set_yticklabels(ylabels, fontsize=8)
    ax.set_ylim(-0.5, len(lanes) - 0.5)
    ax.set_xlim(*xrange)
    ax.grid(axis="x", linewidth=0.4, alpha=0.4)
    return list(handles.values())


def main():
    ap = argparse.ArgumentParser(description="tiny-gpu 执行 trace 可视化")
    ap.add_argument("log", nargs="?", help="trace 日志文件路径")
    ap.add_argument("--start", type=int, default=None, help="起始周期")
    ap.add_argument("--end", type=int, default=None, help="结束周期")
    ap.add_argument("--out", default=None, help="输出 PNG 路径")
    ap.add_argument("--no-show", action="store_true", help="不弹窗, 只保存 PNG")
    args = ap.parse_args()

    if args.log:
        log_path = args.log
    else:
        logs = sorted(glob.glob("test/logs/log_*.txt"),
                      key=os.path.getmtime, reverse=True)
        if not logs:
            sys.exit("test/logs 下没有日志, 请先运行 make test_matadd / make test_matmul")
        log_path = logs[0]
    print(f"解析日志: {log_path}")

    data, lanes = parse_log(log_path)
    all_cycles = sorted({k[0] for k in data})
    start = args.start if args.start is not None else min(all_cycles)
    end = args.end if args.end is not None else max(all_cycles)

    core_runs = build_runs(data, lanes, "core")
    lsu_runs = build_runs(data, lanes, "lsu")
    ylabels = [f"C{c}·T{t}" for c, t in lanes]

    fig, (ax1, ax2) = plt.subplots(
        2, 1, sharex=True, figsize=(14, max(4, len(lanes) * 0.9)),
        gridspec_kw={"height_ratios": [2, 1.4]})
    fig.suptitle(f"tiny-gpu 执行流水线 (cycles {start}~{end})\n{os.path.basename(log_path)}", fontsize=12)

    h1 = draw_band(ax1, lanes, core_runs, STATE_COLORS, ylabels, (start, end))
    ax1.set_ylabel("Core 流水线状态")
    ax1.legend(handles=h1, loc="upper right", ncol=4, fontsize=8)

    h2 = draw_band(ax2, lanes, lsu_runs, LSU_COLORS, ylabels, (start, end))
    ax2.set_ylabel("LSU 状态")
    ax2.set_xlabel("周期 (cycle)")
    ax2.legend(handles=h2, loc="upper right", ncol=4, fontsize=8)

    plt.xticks(range(start, end + 1, max(1, (end - start) // 24)), fontsize=7)
    plt.tight_layout()

    out = args.out or f"{log_path}.png"
    plt.savefig(out, dpi=150)
    print(f"已保存: {out}")

    wait_ct = sum(1 for k in data if data[k]["core"] == "WAIT")
    total = sum(1 for k in data)
    print(f"线程×周期总数: {total}, 其中 WAIT 占 {wait_ct} ({100.0 * wait_ct / total:.1f}%)")

    if not args.no_show and "DISPLAY" in os.environ:
        plt.show()


if __name__ == "__main__":
    main()