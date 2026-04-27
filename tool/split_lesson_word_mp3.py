#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
将「整课单词」MP3（gh-pages：`assets/audio/word/{okey}.mp3`）按静音切成逐词 MP3，
与 lessons_bundle.json 中该课单词 **idx 顺序** 对齐（初级 `lesson==001`；中级 `lesson` 为 `m011` 等，按 `m01` 前缀筛选，与 App 的 `lesson_repository` 一致）。

若合并后的有声段数与单词数仍不一致：有声段**多**则前 N 个与词书按 idx 对齐写出，**余下段保留**，文件名从词书最大 idx+1 起连续四位（如 0057.mp3）；有声段**少**则只输出前若干词的切片（stderr 会提示）。

默认输出（与 Piper 单课目录一致，便于统一资源树）：

  assets/single_words/{okey}/0001.mp3
  assets/single_words/{okey}/0002.mp3
  …
  assets/single_words/{okey}/_split_report.csv

依赖：本机已安装 ffmpeg / ffprobe，且在 PATH 中可调用。

单课：

  python tool/split_lesson_word_mp3.py --okey l1

全部已有整课 word MP3 的课（跳过不存在的 mp3）：

  python tool/split_lesson_word_mp3.py --all
  python tool/split_lesson_word_mp3.py --all --continue-on-error

调参示例：

  python tool/split_lesson_word_mp3.py --okey m3 --merge-strategy forward --merge-short 0.28
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import subprocess
import sys
from pathlib import Path


def project_root() -> Path:
    return Path(__file__).resolve().parent.parent


def okey_to_lesson_code(okey: str) -> str:
    c = okey[0].lower()
    n = int(okey[1:])
    if c == "l":
        return f"{n:03d}"
    return f"m{n:02d}"


def words_for_okey(data: dict, okey: str, lcode: str) -> list[dict]:
    """
    与 lib/lesson_repository.dart 一致：初级单词 lesson 为 001 / 002（精确匹配）；
    中级为 m011、m012…（以 m01、m02 等 lkey 为前缀）。
    """
    raw = data.get("words") or []
    rows: list[dict] = []
    if okey[0].lower() == "m":
        for w in raw:
            wl = str(w.get("lesson") or "")
            if wl.startswith(lcode):
                rows.append(w)
    else:
        for w in raw:
            if (w.get("lesson") or "") == lcode:
                rows.append(w)
    rows.sort(key=lambda w: int(str(w.get("idx", "0"))))
    return rows


def bundle_okeys(data: dict) -> list[str]:
    level1 = data.get("level1") or {}
    level2 = data.get("level2") or {}
    keys = list(level1.keys()) + list(level2.keys())

    def sort_key(k: str) -> tuple[str, int]:
        return (k[0].lower(), int(k[1:]))

    keys.sort(key=sort_key)
    return keys


def ffmpeg_speech_segments(
    mp3: Path,
    *,
    noise: str,
    silence_dur: float,
    total_duration: float,
) -> list[tuple[float, float]]:
    af = f"silencedetect=noise={noise}:d={silence_dur}"
    p = subprocess.run(
        [
            "ffmpeg",
            "-nostats",
            "-i",
            str(mp3),
            "-af",
            af,
            "-f",
            "null",
            "-",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    err = p.stderr or ""
    starts = [float(m.group(1)) for m in re.finditer(r"silence_start: ([\d.]+)", err)]
    ends = [float(m.group(1)) for m in re.finditer(r"silence_end: ([\d.]+)", err)]
    segs: list[tuple[float, float]] = []
    cursor = 0.0
    for s, e in zip(starts, ends):
        if s > cursor + 1e-4:
            segs.append((cursor, s))
        cursor = e
    if total_duration > cursor + 1e-4:
        segs.append((cursor, total_duration))
    return segs


def merge_short_forward(segs: list[tuple[float, float]], th: float) -> list[tuple[float, float]]:
    out: list[tuple[float, float]] = []
    i = 0
    while i < len(segs):
        a, b = segs[i]
        if b - a < th and i + 1 < len(segs):
            na, nb = segs[i + 1]
            out.append((a, nb))
            i += 2
        else:
            out.append((a, b))
            i += 1
    return out


def merge_short_backward(segs: list[tuple[float, float]], th: float) -> list[tuple[float, float]]:
    out: list[tuple[float, float]] = []
    for a, b in segs:
        if out and (b - a) < th:
            pa, _pb = out[-1]
            out[-1] = (pa, b)
        else:
            out.append((a, b))
    return out


def ffprobe_duration(mp3: Path) -> float:
    p = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(mp3),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return float((p.stdout or "").strip())


def ffmpeg_extract_clip(src: Path, start: float, end: float, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    dur = max(0.05, end - start)
    # 不写 ID3v2 / Xing：部分 Android Media3 对「以 ID3 开头的极短 MP3」嗅探失败
    # （UnrecognizedInputFormat / Mp3Extractor sniff NoDeclaredBrand）。
    cmd = [
        "ffmpeg",
        "-y",
        "-ss",
        f"{start:.6f}",
        "-i",
        str(src),
        "-t",
        f"{dur:.6f}",
        "-map_metadata",
        "-1",
        "-c:a",
        "libmp3lame",
        "-b:a",
        "128k",
        "-write_xing",
        "0",
        "-id3v2_version",
        "0",
        str(dst),
    ]
    subprocess.run(cmd, capture_output=True, check=True)


def split_one_lesson(
    root: Path,
    okey: str,
    *,
    src: Path | None,
    out_dir: Path | None,
    silence_noise: str,
    silence_dur: float,
    merge_strategy: str,
    merge_short: float,
    dry_run: bool,
    force: bool,
) -> tuple[int, str]:
    """
    返回 (exit_code, message)。
    exit_code 0 成功；1 失败（源缺失、词数为 0、ffmpeg 错误、文件已存在且未 --force）。
    有声段与单词数不一致时截断对齐，不再视为失败。
    """
    okey = okey.strip().lower()
    mp3 = src or (root / "assets" / "audio" / "word" / f"{okey}.mp3")
    if not mp3.is_file():
        return 1, f"跳过：无源文件 {mp3.relative_to(root)}"

    bundle = root / "assets" / "data" / "lessons_bundle.json"
    if not bundle.is_file():
        return 1, f"找不到 {bundle}"

    data = json.loads(bundle.read_text(encoding="utf-8"))
    lcode = okey_to_lesson_code(okey)
    words = words_for_okey(data, okey, lcode)
    if not words:
        return 1, f"跳过：lesson={lcode} 词数为 0"

    total = ffprobe_duration(mp3)
    raw = ffmpeg_speech_segments(
        mp3,
        noise=silence_noise,
        silence_dur=silence_dur,
        total_duration=total,
    )
    segs = raw
    if merge_strategy in ("backward", "both"):
        segs = merge_short_backward(segs, merge_short)
    if merge_strategy in ("forward", "both"):
        segs = merge_short_forward(segs, merge_short)

    n_words_full = len(words)
    n_seg_full = len(segs)
    max_word_idx = max(int(str(w.get("idx", 0))) for w in words) if words else 0

    align_note = ""
    if n_seg_full > n_words_full:
        n_extra = n_seg_full - n_words_full
        align_note = (
            f"（保留）有声段多 {n_extra} 条：前 {n_words_full} 段按词书 idx 命名，"
            f"余下自 {max_word_idx + 1:04d}.mp3 起连续编号。"
        )
        print(f"[{okey}] {align_note}", file=sys.stderr)
    elif n_seg_full < n_words_full:
        words = words[:n_seg_full]
        align_note = (
            f"（对齐）有声段少 {n_words_full - n_seg_full} 条，已截断词表；"
            f"仅输出前 {n_seg_full} 词的切片（至 idx={words[-1].get('idx') if words else ''}）。"
        )
        print(f"[{okey}] {align_note}", file=sys.stderr)

    n_words = len(words)
    n_seg = len(segs)
    head = (
        f"{okey} lesson={lcode} 单词(词书)={n_words_full} 有声段 raw={len(raw)} -> 合并后={n_seg_full}"
        f" -> 写出 {n_seg} 个 mp3（词书对齐 {n_words} 个）"
    )

    dest_root = out_dir or (root / "assets" / "single_words" / okey)
    report = dest_root / "_split_report.csv"

    rows: list[tuple[str, str, float, float, float, str]] = []
    for i, w in enumerate(words):
        if i >= n_seg:
            break
        t0, t1 = segs[i]
        idx = str(w.get("idx", ""))
        kana = str(w.get("kana", "")).replace("\n", " ")[:40]
        rows.append((okey, idx, t0, t1, t1 - t0, kana))
    for j in range(n_words, n_seg):
        t0, t1 = segs[j]
        num = max_word_idx + (j - n_words + 1)
        rows.append((okey, str(num), t0, t1, t1 - t0, ""))

    if dry_run:
        return 0, f"{head}\n  dry-run 前 3 条: {rows[:3]}\n  … 后 2 条: {rows[-2:]}"

    dest_root.mkdir(parents=True, exist_ok=True)
    for i, w in enumerate(words):
        if i >= n_seg:
            break
        t0, t1 = segs[i]
        idx = int(str(w.get("idx", "0")))
        dst = dest_root / f"{idx:04d}.mp3"
        if dst.exists() and not force:
            return (
                1,
                f"{head}\n  已存在 {dst.relative_to(root)}（加 --force 覆盖）",
            )
        ffmpeg_extract_clip(mp3, t0, t1, dst)
    for j in range(n_words, n_seg):
        t0, t1 = segs[j]
        num = max_word_idx + (j - n_words + 1)
        dst = dest_root / f"{num:04d}.mp3"
        if dst.exists() and not force:
            return (
                1,
                f"{head}\n  已存在 {dst.relative_to(root)}（加 --force 覆盖）",
            )
        ffmpeg_extract_clip(mp3, t0, t1, dst)

    with report.open("w", encoding="utf-8", newline="") as f:
        cw = csv.writer(f)
        cw.writerow(["okey", "idx", "start_sec", "end_sec", "duration_sec", "kana"])
        cw.writerows(rows)

    tail = f"已写入 {dest_root.relative_to(root)} 共 {n_seg} 个 mp3 与 _split_report.csv"
    if align_note:
        tail = f"{align_note}\n  {tail}"
    return 0, f"{head}\n  {tail}"


def main() -> int:
    root = project_root()
    ap = argparse.ArgumentParser(description="按静音切分整课单词 MP3 → assets/single_words/{okey}/")
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--okey", help="单课，如 l1、m12")
    g.add_argument("--all", action="store_true", help="处理 bundle 中全部 okey（仅当 assets/audio/word/{okey}.mp3 存在）")
    ap.add_argument("--input", type=Path, help="覆盖默认源 MP3 路径")
    ap.add_argument(
        "--out-dir",
        type=Path,
        help="覆盖默认输出目录（默认 assets/single_words/{okey}/）",
    )
    ap.add_argument("--silence-noise", default="-35dB")
    ap.add_argument("--silence-dur", type=float, default=0.25)
    ap.add_argument("--merge-strategy", choices=("backward", "forward", "both"), default="backward")
    ap.add_argument("--merge-short", type=float, default=0.25)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true", help="覆盖已存在的 0001.mp3 等")
    ap.add_argument(
        "--continue-on-error",
        action="store_true",
        help="与 --all 合用：单课失败时继续，最后若有失败则退出码 1",
    )
    args = ap.parse_args()

    def run_one(ok: str) -> tuple[int, str]:
        single = bool(args.okey)
        return split_one_lesson(
            root,
            ok,
            src=args.input if single else None,
            out_dir=args.out_dir if single else None,
            silence_noise=args.silence_noise,
            silence_dur=args.silence_dur,
            merge_strategy=args.merge_strategy,
            merge_short=args.merge_short,
            dry_run=args.dry_run,
            force=args.force,
        )

    if args.okey:
        code, msg = run_one(args.okey)
        print(msg)
        return code

    data = json.loads((root / "assets" / "data" / "lessons_bundle.json").read_text(encoding="utf-8"))
    keys = bundle_okeys(data)
    failures: list[str] = []
    skipped = 0
    for ok in keys:
        mp3 = root / "assets" / "audio" / "word" / f"{ok}.mp3"
        if not mp3.is_file():
            skipped += 1
            print(f"[skip] 无源: {mp3.relative_to(root)}")
            continue
        code, msg = run_one(ok)
        print(msg)
        if code != 0:
            failures.append(ok)
            if not args.continue_on_error:
                print(f"\n--all 在 {ok} 失败；可加 --continue-on-error 跳过其余错误", file=sys.stderr)
                return 1

    print(f"\n--all 完成：处理 {len(keys) - skipped} 个有 mp3 的课，跳过无源 {skipped} 个。")
    if failures:
        print(f"失败 {len(failures)} 课: {', '.join(failures)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
