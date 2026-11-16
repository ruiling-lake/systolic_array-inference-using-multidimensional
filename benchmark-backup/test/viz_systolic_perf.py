#!/usr/bin/env python3
"""脉动阵列加速效果可视化: 4x4 vs 16x16 vs 32x32 处理 28x28 MNIST 图的计算时间。

数据来源: 各项目 results.xml 里 cocotb 实测的单次 GEMM 仿真周期数。

模型: 把一张 28x28 图的运算看成一次 28x28x28 的分块 GEMM。
   分块数 = ceil(28/S)^3  (输出分块 x 输出分块 x K 方向分块)
   图像耗时 = 分块数 x 单次 GEMM 实测周期 x 时钟周期(10ns @100MHz)

用法:
    python3 test/viz_systolic_perf.py            # 保存为 test/viz/systolic_perf.png
    python3 test/viz_systolic_perf.py --no-show  # 不弹窗
"""
import argparse
import os
import re
import sys

import matplotlib.pyplot as plt
from matplotlib import font_manager

for f in font_manager.findSystemFonts(fontpaths=["/usr/share/fonts/opentype/noto"]):
    if "CJK" in f:
        font_manager.fontManager.addfont(f)
plt.rcParams["font.sans-serif"] = ["Noto Sans CJK JP", "DejaVu Sans"]
plt.rcParams["axes.unicode_minus"] = False

WORKSPACE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # tiny-gpu 根目录
PROJECTS = [
    (4,  WORKSPACE),
    (16, os.path.expanduser("~/Desktop/16x16_systolic_array")),
    (32, os.path.expanduser("~/Desktop/32x32_systolic_array")),
]
CLOCK_NS = 10   # 100 MHz
IMG_N = 28      # MNIST 图片 28x28
RESET_NS = 30   # 测试复位等固定开销 (约 3 周期)


def read_gemm_cycles(project_dir):
    """从 results.xml 读取最近一次单次 GEMM 仿真周期数。"""
    xml_path = os.path.join(project_dir, "results.xml")
    with open(xml_path) as f:
        content = f.read()
    m = re.search(r'sim_time_ns="([\d.]+)"', content)
    if not m:
        sys.exit(f"无法从 {xml_path} 解析 sim_time_ns")
    cycles = round((float(m.group(1)) - RESET_NS) / CLOCK_NS)
    tcase = re.search(r'name="([^"]+)"', content)
    return cycles, (tcase.group(1) if tcase else "?")


def main():
    ap = argparse.ArgumentParser(description="脉动阵列加速效果可视化")
    ap.add_argument("--no-show", action="store_true", help="不弹窗, 只保存 PNG")
    ap.add_argument("--out", default=None, help="输出 PNG 路径")
    args = ap.parse_args()

    sizes, gemm_cycles, labels = [], [], []
    for s, d in PROJECTS:
        cycles, tname = read_gemm_cycles(d)
        sizes.append(s)
        gemm_cycles.append(cycles)
        labels.append(f"{s}x{s}\n({tname})")

    # ---- 28x28 图计算时间模型: 分块 GEMM ----
    calls = [((IMG_N + s - 1) // s) ** 3 for s in sizes]
    img_cycles = [c * g for c, g in zip(calls, gemm_cycles)]
    img_us = [cyc * CLOCK_NS / 1000.0 for cyc in img_cycles]
    speedup = [img_us[0] / u for u in img_us]

    print("=" * 66)
    print(f"{'脉动阵列':<12}{'单次GEMM(cycles)':>18}{'整图分块数':>10}{'28x28图耗时(us)':>16}{'加速比':>8}")
    for s, c, n, u, sp in zip(sizes, gemm_cycles, calls, img_us, speedup):
        print(f"{s}x{s:<10}{c:>16}{n:>10}{u:>14.1f}{'':>2}{sp:>6.2f}x")
    print(f"模型: 28x28 图 = {IMG_N}x{IMG_N}x{IMG_N} 分块 GEMM, 分块数=ceil(28/S)^3, @100MHz")
    print("=" * 66)

    colors = ["#42A5F5", "#66BB6A", "#FF7043"]
    fig, axes = plt.subplots(1, 3, figsize=(15, 5))
    fig.suptitle(
        f"脉动阵列加速效果对比 (处理 28x28 MNIST 图, 实测数据, @100MHz)",
        fontsize=13)

    ax = axes[0]
    bars = ax.barh([f"{s}x{s}" for s in sizes], img_us, color=colors)
    for b, (u, sp, s) in zip(bars, zip(img_us, speedup, sizes)):
        ax.text(b.get_width() + 6, b.get_y() + b.get_height() / 2,
                f"{u:.0f}us  ({sp:.2f}x)", va="center", fontsize=10)
    ax.set_title("28x28 图计算耗时 (分块 GEMM 模型)", fontsize=11)
    ax.set_xlabel("时间 (μs)")
    ax.set_xlim(0, max(img_us) * 1.18)

    ax = axes[1]
    bars = ax.barh([f"{s}x{s}" for s in sizes], gemm_cycles, color=colors)
    for b, c in zip(bars, gemm_cycles):
        ax.text(b.get_width() * 1.02, b.get_y() + b.get_height() / 2,
                f"{c} cycles", va="center", fontsize=10)
    ax.set_title("单次 LeNet GEMM 实测延迟", fontsize=11)
    ax.set_xlabel("周期 (cycles)")
    ax.set_xscale("log")
    ax.set_xlim(100, max(gemm_cycles) * 2)

    ax = axes[2]
    peak = [s * s for s in sizes]
    bars = ax.barh([f"{s}x{s}" for s in sizes], peak, color=colors)
    for b, p in zip(bars, peak):
        ax.text(b.get_width() * 1.01, b.get_y() + b.get_height() / 2,
                f"{p} MAC/cyc", va="center", fontsize=10)
    ax.set_title("阵列峰值吞吐 (PE 数)", fontsize=11)
    ax.set_xlabel("MAC/cycle")
    ax.set_xlim(0, max(peak) * 1.25)

    for a in axes:
        a.grid(axis="x", linewidth=0.4, alpha=0.5)
        a.invert_yaxis()

    fig.text(0.01, 0.01,
             "数据来源: 各项目 results.xml 实测单次 GEMM 周期数; 图像耗时=ceil(28/S)^3 Gx 单次延迟",
             fontsize=8, color="grey")
    plt.tight_layout()

    out = args.out or os.path.join(WORKSPACE, "test", "viz", "systolic_perf.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    plt.savefig(out, dpi=150)
    print(f"\n已保存: {out}")

    if not args.no_show and "DISPLAY" in os.environ:
        plt.show()


if __name__ == "__main__":
    main()