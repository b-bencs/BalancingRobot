#!/usr/bin/env python3
"""Generate publication-style charts from the saved PID mode measurements."""

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.colors import ListedColormap


SCRIPT_DIR = Path(__file__).resolve().parent
MEASUREMENTS_DIR = SCRIPT_DIR.parent
FALL_THRESHOLD_RAD = 0.785

RUNS = [
    {
        "condition": "clean",
        "label": "Clean",
        "summary": "pid_modes_20260603_203614/clean_summary.csv",
        "folder": "pid_modes_20260603_203614",
    },
    {
        "condition": "net10",
        "label": "Network 10 ms",
        "summary": "pid_modes_netdeg10_20260603_210000/net10_summary.csv",
        "folder": "pid_modes_netdeg10_20260603_210000",
    },
    {
        "condition": "net20",
        "label": "Network 20 ms",
        "summary": "pid_modes_netdeg_20260603_205128/net20_summary.csv",
        "folder": "pid_modes_netdeg_20260603_205128",
    },
    {
        "condition": "k8s_highprio_cpu",
        "label": "K8s high-priority CPU",
        "summary": (
            "pid_modes_k8s_highprio_cpu_20260604_124158/"
            "pid_modes_k8s_highprio_cpu_summary.csv"
        ),
        "folder": "pid_modes_k8s_highprio_cpu_20260604_124158",
    },
]

MODES = ["be", "gd", "edf"]
MODE_LABELS = {"be": "BE", "gd": "GD", "edf": "EDF"}
MODE_COLORS = {"be": "#C44E52", "gd": "#DD8452", "edf": "#4C72B0"}


def parse_restart_delta(value):
    if pd.isna(value):
        return np.nan, np.nan, np.nan
    text = str(value).strip().replace("->", ">")
    if ">" not in text:
        return np.nan, np.nan, np.nan
    before, after = text.split(">", 1)
    try:
        before_i = int(before)
        after_i = int(after)
    except ValueError:
        return np.nan, np.nan, np.nan
    return before_i, after_i, after_i - before_i


def load_summary():
    frames = []
    for run in RUNS:
        path = MEASUREMENTS_DIR / run["summary"]
        frame = pd.read_csv(path)
        frame["condition"] = run["condition"]
        frame["condition_label"] = run["label"]
        frame["mode"] = frame["mode"].str.lower()
        frames.append(frame)

    summary = pd.concat(frames, ignore_index=True)
    restart_values = summary["robot_restarts_before_after"].apply(parse_restart_delta)
    summary["restart_before"] = [item[0] for item in restart_values]
    summary["restart_after"] = [item[1] for item in restart_values]
    summary["restart_delta"] = [item[2] for item in restart_values]
    summary["fell_bool"] = summary["fell"].astype(str).str.lower().eq("yes")
    summary.to_csv(SCRIPT_DIR / "combined_chart_input.csv", index=False)
    return summary


def style_axes(ax):
    ax.grid(True, axis="y", color="#d7d7d7", linewidth=0.8, alpha=0.7)
    ax.set_axisbelow(True)
    for spine in ["top", "right"]:
        ax.spines[spine].set_visible(False)
    ax.spines["left"].set_color("#aaaaaa")
    ax.spines["bottom"].set_color("#aaaaaa")


def save_figure(fig, filename):
    path = SCRIPT_DIR / filename
    fig.savefig(path, dpi=180, bbox_inches="tight")
    plt.close(fig)
    print(path)


def metric_values(summary, metric, condition):
    values = []
    for mode in MODES:
        rows = summary[
            (summary["condition"] == condition) & (summary["mode"] == mode)
        ]
        if rows.empty:
            values.append(np.nan)
        else:
            values.append(float(rows.iloc[0][metric]))
    return values


def plot_summary_metric_grid(summary):
    fig, axes = plt.subplots(2, 2, figsize=(13.5, 8.5))
    fig.suptitle("PID Mode Measurement Summary", fontsize=16, fontweight="bold")

    metrics = [
        ("max_abs_angle", "Max absolute angle [rad]", "Max angle"),
        ("influx_timeout_samples", "Influx timeout samples [count]", "Timeout samples"),
        ("pid_request_p95_ms", "PID HTTP p95 [ms]", "PID p95 latency"),
        ("sample_hz", "Effective sample rate [Hz]", "Sample rate"),
    ]

    x = np.arange(len(RUNS))
    width = 0.24
    for ax, (metric, ylabel, title) in zip(axes.ravel(), metrics):
        for index, mode in enumerate(MODES):
            values = [
                metric_values(summary, metric, run["condition"])[index]
                for run in RUNS
            ]
            offset = (index - 1) * width
            bars = ax.bar(
                x + offset,
                values,
                width,
                label=MODE_LABELS[mode],
                color=MODE_COLORS[mode],
            )
            if metric == "max_abs_angle":
                for run_index, bar in enumerate(bars):
                    row = summary[
                        (summary["condition"] == RUNS[run_index]["condition"])
                        & (summary["mode"] == mode)
                    ].iloc[0]
                    if row["fell_bool"]:
                        ax.text(
                            bar.get_x() + bar.get_width() / 2,
                            bar.get_height() + 0.04,
                            "fell",
                            ha="center",
                            va="bottom",
                            fontsize=8,
                            fontweight="bold",
                            color="#8b0000",
                        )
        if metric == "max_abs_angle":
            ax.axhline(
                FALL_THRESHOLD_RAD,
                color="#222222",
                linestyle="--",
                linewidth=1,
                label="fall threshold",
            )
        ax.set_title(title, fontsize=12, fontweight="bold")
        ax.set_ylabel(ylabel)
        ax.set_xticks(x)
        ax.set_xticklabels([run["label"] for run in RUNS], rotation=15, ha="right")
        style_axes(ax)

    axes[0, 0].legend(frameon=False, ncols=4, fontsize=9)
    fig.tight_layout(rect=[0, 0, 1, 0.96])
    save_figure(fig, "summary_metric_grid.png")


def plot_fall_restart_matrix(summary):
    matrix = np.zeros((len(RUNS), len(MODES)))
    labels = []

    for run_index, run in enumerate(RUNS):
        row_labels = []
        for mode_index, mode in enumerate(MODES):
            row = summary[
                (summary["condition"] == run["condition"]) & (summary["mode"] == mode)
            ].iloc[0]
            if row["fell_bool"]:
                matrix[run_index, mode_index] = 2
                state = "FELL"
            elif row["restart_delta"] > 0 or row["influx_timeout_samples"] > 0:
                matrix[run_index, mode_index] = 1
                state = "DEGRADED"
            else:
                matrix[run_index, mode_index] = 0
                state = "CLEAN"
            row_labels.append(
                f"{state}\n"
                f"to={int(row['influx_timeout_samples'])}\n"
                f"r={row['robot_restarts_before_after']}\n"
                f"p95={row['pid_request_p95_ms']:.1f} ms"
            )
        labels.append(row_labels)

    fig, ax = plt.subplots(figsize=(9.5, 6.2))
    cmap = ListedColormap(["#5DAE68", "#E7B85A", "#C44E52"])
    ax.imshow(matrix, cmap=cmap, vmin=0, vmax=2)
    ax.set_title("Run Health Matrix", fontsize=15, fontweight="bold")
    ax.set_xticks(np.arange(len(MODES)))
    ax.set_xticklabels([MODE_LABELS[mode] for mode in MODES], fontsize=12)
    ax.set_yticks(np.arange(len(RUNS)))
    ax.set_yticklabels([run["label"] for run in RUNS], fontsize=11)

    for run_index in range(len(RUNS)):
        for mode_index in range(len(MODES)):
            color = "white" if matrix[run_index, mode_index] == 2 else "#222222"
            ax.text(
                mode_index,
                run_index,
                labels[run_index][mode_index],
                ha="center",
                va="center",
                fontsize=9,
                color=color,
                fontweight="bold",
            )

    for spine in ax.spines.values():
        spine.set_visible(False)
    ax.tick_params(length=0)
    fig.tight_layout()
    save_figure(fig, "fall_restart_health_matrix.png")


def read_angle_csv(run, mode):
    path = MEASUREMENTS_DIR / run["folder"] / mode / "angle.csv"
    frame = pd.read_csv(path)
    frame["time_s"] = (frame["time"] - frame["time"].min()) / 1_000_000_000.0
    frame["mode"] = mode
    return frame


def plot_angle_traces():
    fig, axes = plt.subplots(2, 2, figsize=(14, 8.5), sharey=True)
    fig.suptitle("Robot Angle Over Time", fontsize=16, fontweight="bold")

    for ax, run in zip(axes.ravel(), RUNS):
        for mode in MODES:
            frame = read_angle_csv(run, mode)
            ax.plot(
                frame["time_s"],
                frame["value"],
                label=MODE_LABELS[mode],
                color=MODE_COLORS[mode],
                linewidth=1.4,
                alpha=0.9,
            )
        ax.axhline(FALL_THRESHOLD_RAD, color="#222222", linestyle="--", linewidth=1)
        ax.axhline(-FALL_THRESHOLD_RAD, color="#222222", linestyle="--", linewidth=1)
        ax.set_title(run["label"], fontsize=12, fontweight="bold")
        ax.set_xlabel("time inside measured window [s]")
        ax.set_ylabel("angle [rad]")
        ax.set_ylim(-2.15, 2.15)
        style_axes(ax)

    axes[0, 0].legend(frameon=False, ncols=3, fontsize=9)
    fig.tight_layout(rect=[0, 0, 1, 0.96])
    save_figure(fig, "angle_traces_by_condition.png")


def plot_nonfallen_angle_zoom(summary):
    fig, axes = plt.subplots(2, 2, figsize=(14, 8.5), sharey=True)
    fig.suptitle(
        "Robot Angle Zoom for Non-Fallen Runs", fontsize=16, fontweight="bold"
    )

    for ax, run in zip(axes.ravel(), RUNS):
        plotted_any = False
        for mode in MODES:
            row = summary[
                (summary["condition"] == run["condition"]) & (summary["mode"] == mode)
            ].iloc[0]
            if row["fell_bool"]:
                continue
            frame = read_angle_csv(run, mode)
            ax.plot(
                frame["time_s"],
                frame["value"],
                label=MODE_LABELS[mode],
                color=MODE_COLORS[mode],
                linewidth=1.4,
                alpha=0.9,
            )
            plotted_any = True
        if not plotted_any:
            ax.text(
                0.5,
                0.5,
                "all modes fell",
                ha="center",
                va="center",
                transform=ax.transAxes,
                fontsize=13,
                fontweight="bold",
                color="#555555",
            )
        ax.set_title(run["label"], fontsize=12, fontweight="bold")
        ax.set_xlabel("time inside measured window [s]")
        ax.set_ylabel("angle [rad]")
        ax.set_ylim(-0.04, 0.04)
        style_axes(ax)

    axes[0, 0].legend(frameon=False, ncols=3, fontsize=9)
    fig.tight_layout(rect=[0, 0, 1, 0.96])
    save_figure(fig, "angle_zoom_nonfallen_runs.png")


def plot_pid_latency(summary):
    fig, axes = plt.subplots(1, 2, figsize=(13, 5.2))
    fig.suptitle("PID HTTP Latency From Robot Logs", fontsize=16, fontweight="bold")
    metrics = [
        ("pid_request_p95_ms", "p95 latency [ms]", "PID p95"),
        ("pid_request_max_ms", "max latency [ms]", "PID max"),
    ]
    x = np.arange(len(RUNS))
    width = 0.24

    for ax, (metric, ylabel, title) in zip(axes, metrics):
        for index, mode in enumerate(MODES):
            values = [
                metric_values(summary, metric, run["condition"])[index]
                for run in RUNS
            ]
            ax.bar(
                x + (index - 1) * width,
                values,
                width,
                label=MODE_LABELS[mode],
                color=MODE_COLORS[mode],
            )
        ax.set_title(title, fontsize=12, fontweight="bold")
        ax.set_ylabel(ylabel)
        ax.set_xticks(x)
        ax.set_xticklabels([run["label"] for run in RUNS], rotation=15, ha="right")
        style_axes(ax)

    axes[0].legend(frameon=False, ncols=3, fontsize=9)
    fig.tight_layout(rect=[0, 0, 1, 0.93])
    save_figure(fig, "pid_latency_comparison.png")


def plot_network_trends(summary):
    network_conditions = ["clean", "net10", "net20"]
    network_labels = ["Clean", "10 ms", "20 ms"]
    metrics = [
        ("max_abs_angle", "max absolute angle [rad]", "Angle degradation"),
        ("influx_timeout_samples", "timeout samples [count]", "Timeout samples"),
        ("pid_request_p95_ms", "PID p95 [ms]", "PID p95 latency"),
    ]

    fig, axes = plt.subplots(1, 3, figsize=(15, 4.8))
    fig.suptitle("Network Degradation Trend", fontsize=16, fontweight="bold")
    x = np.arange(len(network_conditions))

    for ax, (metric, ylabel, title) in zip(axes, metrics):
        for mode in MODES:
            values = []
            for condition in network_conditions:
                row = summary[
                    (summary["condition"] == condition) & (summary["mode"] == mode)
                ].iloc[0]
                values.append(float(row[metric]))
            ax.plot(
                x,
                values,
                marker="o",
                linewidth=2,
                label=MODE_LABELS[mode],
                color=MODE_COLORS[mode],
            )
        if metric == "max_abs_angle":
            ax.axhline(FALL_THRESHOLD_RAD, color="#222222", linestyle="--", linewidth=1)
        ax.set_title(title, fontsize=12, fontweight="bold")
        ax.set_ylabel(ylabel)
        ax.set_xticks(x)
        ax.set_xticklabels(network_labels)
        style_axes(ax)

    axes[0].legend(frameon=False, fontsize=9)
    fig.tight_layout(rect=[0, 0, 1, 0.93])
    save_figure(fig, "network_degradation_trend.png")


def plot_cpu_focus(summary):
    cpu = summary[summary["condition"] == "k8s_highprio_cpu"].copy()
    metrics = [
        ("max_abs_angle", "max abs angle [rad]", "Angle"),
        ("pid_request_p95_ms", "PID p95 [ms]", "PID latency"),
        ("influx_timeout_samples", "timeout samples [count]", "Timeouts"),
        ("sample_hz", "sample rate [Hz]", "Sample rate"),
    ]

    fig, axes = plt.subplots(2, 2, figsize=(12.5, 8))
    fig.suptitle("Kubernetes High-Priority CPU Stress", fontsize=16, fontweight="bold")
    x = np.arange(len(MODES))

    for ax, (metric, ylabel, title) in zip(axes.ravel(), metrics):
        rows = [cpu[cpu["mode"] == mode].iloc[0] for mode in MODES]
        values = [float(row[metric]) for row in rows]
        bars = ax.bar(
            x,
            values,
            color=[MODE_COLORS[mode] for mode in MODES],
            width=0.55,
        )
        if metric == "max_abs_angle":
            ax.axhline(FALL_THRESHOLD_RAD, color="#222222", linestyle="--", linewidth=1)
        for bar, row in zip(bars, rows):
            if row["fell_bool"]:
                ax.text(
                    bar.get_x() + bar.get_width() / 2,
                    bar.get_height() + max(values) * 0.03,
                    "fell",
                    ha="center",
                    va="bottom",
                    fontsize=9,
                    fontweight="bold",
                    color="#8b0000",
                )
        ax.set_title(title, fontsize=12, fontweight="bold")
        ax.set_ylabel(ylabel)
        ax.set_xticks(x)
        ax.set_xticklabels([MODE_LABELS[mode] for mode in MODES])
        style_axes(ax)

    fig.tight_layout(rect=[0, 0, 1, 0.94])
    save_figure(fig, "k8s_highprio_cpu_focus.png")


def main():
    plt.rcParams.update(
        {
            "font.size": 10,
            "figure.facecolor": "white",
            "axes.facecolor": "white",
            "axes.titlepad": 10,
            "savefig.facecolor": "white",
        }
    )
    summary = load_summary()
    plot_summary_metric_grid(summary)
    plot_fall_restart_matrix(summary)
    plot_angle_traces()
    plot_nonfallen_angle_zoom(summary)
    plot_pid_latency(summary)
    plot_network_trends(summary)
    plot_cpu_focus(summary)


if __name__ == "__main__":
    main()
