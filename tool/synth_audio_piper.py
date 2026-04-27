#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
使用 piper-plus（python -m piper）从 lessons_bundle 批量合成日语 WAV，
输出到 assets/audio/word/ 与 assets/audio/lesson/，与 fetch_audio.dart 目录一致。

首次使用请先安装依赖并下载模型：

  pip install -r tool/requirements-piper.txt
  python tool/synth_audio_piper.py --download-model

再执行合成（可加 --force 覆盖已有 wav）：

  python tool/synth_audio_piper.py
  python tool/synth_audio_piper.py --word-only
  python tool/synth_audio_piper.py --lesson-only
  python tool/synth_audio_piper.py --only l1 --word-only

词书按课输出到 assets/single_words/初级第01课/（每词一个 wav，见 --single-words-lesson）：

  python tool/synth_audio_piper.py --single-words-lesson 1
  python tool/synth_audio_piper.py --single-words-lesson m1 --force
  python tool/synth_audio_piper.py --single-words-all
  python tool/synth_audio_piper.py --single-words-lesson 1 --single-words-merge

长句冒烟测试（不读 lessons_bundle，仅验证模型能否稳定出 wav）：

  python tool/synth_audio_piper.py --piper-smoke-long
  python tool/synth_audio_piper.py --piper-smoke-long --piper-smoke-out D:/tmp/long.wav

试合成任意短句/单词（不读 lessons_bundle）：

  python tool/synth_audio_piper.py --piper-test-phrase 中国人
  python tool/synth_audio_piper.py --piper-test-phrase 中国人 --piper-test-out tool/chuugokujin.wav

可选：本机已安装 ffmpeg 时，用 --mp3 同时生成 .mp3（课文页当前仅播内置 mp3）。

环境变量：
  PIPER_MODEL   模型名，默认 ja_JP-css10-6lang-medium（日语向，避免多语言模型走英文 g2p）
  PIPER_MODEL_DIR  模型目录，默认 <项目>/tool/.piper_models
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import wave
from pathlib import Path


def project_root() -> Path:
    return Path(__file__).resolve().parent.parent


def strip_ruby(s: str) -> str:
    return re.sub(r"!(.+?)\((.*?)\)", r"\1", s)


def normalize_layout(s: str) -> str:
    t = strip_ruby(s.replace("\r\n", "\n"))
    lines_out: list[str] = []
    for line in t.split("\n"):
        line = line.strip()
        if not line:
            continue
        line = re.sub(r"^(> )?\*[\s　]*", "", line)
        line = re.sub(r"^-\s*", "", line).strip()
        if not line or line in ("-", "---"):
            continue
        lines_out.append(line)
    return "。".join(lines_out)


def truncate(s: str, max_chars: int) -> str:
    if len(s) <= max_chars:
        return s
    return s[: max_chars - 12] + "。以下、長さ制限のため省略。"


def lesson_entry(level1: dict, level2: dict, okey: str) -> dict:
    if okey in level1:
        return dict(level1[okey])
    return dict(level2[okey])


def word_text_primary(obj: dict, okey: str) -> str:
    if okey.startswith("l"):
        basic4 = obj.get("basic4") or ""
        first = ""
        for raw in basic4.split("\n"):
            if raw.strip():
                first = raw
                break
        t = re.sub(r"^> \* ", "", first).strip()
        if t.endswith("。"):
            t = t[:-1]
        t = t.strip()
        if not t:
            t = (obj.get("title") or "").strip()
        return normalize_layout(t)
    texttitle = (obj.get("texttitle") or "").strip()
    text = obj.get("text") or ""
    first_body = ""
    for raw in text.split("\n"):
        if raw.strip():
            first_body = raw
            break
    clip = first_body[:400] if len(first_body) > 400 else first_body
    return normalize_layout(f"{texttitle}。{clip}")


def lesson_text_long(obj: dict, okey: str) -> str:
    if okey.startswith("l"):
        parts = [
            obj.get("title") or "",
            obj.get("basic4") or "",
            obj.get("basicc") or "",
            obj.get("contitle") or "",
            obj.get("context") or "",
        ]
        return normalize_layout("\n".join(parts))
    parts = [
        obj.get("contitle") or "",
        obj.get("conversation") or "",
        obj.get("texttitle") or "",
        obj.get("text") or "",
    ]
    return normalize_layout("\n".join(parts))


def find_onnx(models_dir: Path) -> Path | None:
    if not models_dir.is_dir():
        return None
    all_onnx = list(models_dir.glob("*.onnx"))
    if not all_onnx:
        return None
    # 勿选 ORT 缓存的 *.cpu.opt.onnx：与 config 组合时常见「文件有、播放器 0:00 / 极短无声」。
    cands = [p for p in all_onnx if ".cpu.opt" not in p.name.lower()]
    if not cands:
        cands = all_onnx

    def sort_key(p: Path) -> tuple[int, str]:
        n = p.name.lower()
        if "css10-ja" in n:
            return (0, p.name)
        if "ja" in n or "jp" in n or "tsukuyomi" in n:
            return (1, p.name)
        return (2, p.name)

    return sorted(cands, key=sort_key)[0]


def assert_wav_has_audio(wav_path: Path, min_frames: int = 1200) -> None:
    """检查 Piper 写出的是否为有效波形（避免 0 帧/极短「假成功」）。"""
    try:
        w = wave.open(str(wav_path), "rb")
    except wave.Error as e:
        raise RuntimeError(f"不是有效 WAV 文件: {wav_path} ({e})") from e
    try:
        n = w.getnframes()
        ch = w.getnchannels()
        sw = w.getsampwidth()
        rate = w.getframerate()
    finally:
        w.close()
    if n < min_frames:
        raise RuntimeError(
            f"WAV 无效或近乎无声: nframes={n}, ch={ch}, width={sw}, rate={rate}。"
            " 常见原因：误用 tool/.piper_models 下 ORT 缓存的 *.cpu.opt.onnx（请删除后重跑）；"
            " 或 config.json 与 onnx 不匹配。"
        )


def config_path_for(onnx: Path) -> Path | None:
    p1 = onnx.parent / f"{onnx.stem}.onnx.json"
    if p1.is_file():
        return p1
    p2 = onnx.parent / "config.json"
    if p2.is_file():
        return p2
    return None


def rewav_standard_s16le_44100(src: Path, ffmpeg: str) -> None:
    """用 ffmpeg 转成常见播放器兼容的 mono / 44.1kHz / s16le WAV（覆盖 src）。"""
    tmp = src.with_suffix(".ffmpeg_tmp.wav")
    try:
        r = subprocess.run(
            [
                ffmpeg,
                "-y",
                "-i",
                str(src.resolve()),
                "-ac",
                "1",
                "-ar",
                "44100",
                "-c:a",
                "pcm_s16le",
                str(tmp.resolve()),
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=300,
        )
        if r.returncode != 0:
            raise RuntimeError((r.stderr or r.stdout or "")[:1500])
        tmp.replace(src)
    finally:
        if tmp.exists():
            try:
                tmp.unlink(missing_ok=True)
            except OSError:
                pass


def run_piper(
    *,
    onnx: Path,
    config: Path | None,
    text: str,
    out_wav: Path,
    length_scale: float,
    noise_scale: float,
    noise_w: float | None = None,
    sentence_silence: float = 0.0,
    post_normalize_wav: bool = False,
    ffmpeg_bin: str | None = None,
) -> None:
    out_wav.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        suffix=".txt",
        delete=False,
        prefix="piper_in_",
    ) as tf:
        tf.write(text)
        tmp_txt = Path(tf.name)
    try:
        cmd: list[str] = [
            sys.executable,
            "-m",
            "piper",
            "-m",
            str(onnx.resolve()),
            "-f",
            str(out_wav.resolve()),
            "--length-scale",
            str(length_scale),
            "--noise-scale",
            str(noise_scale),
            "--sentence-silence",
            str(sentence_silence),
            "--input-file",
            str(tmp_txt.resolve()),
        ]
        if noise_w is not None:
            cmd.extend(["--noise-w", str(noise_w)])
        if config is not None:
            cmd.extend(["-c", str(config.resolve())])
        r = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=600,
        )
        if r.returncode != 0:
            err = (r.stderr or "") + (r.stdout or "")
            raise RuntimeError(f"piper failed rc={r.returncode}: {err[:2000]}")
        if not out_wav.exists():
            raise RuntimeError("piper 未写出 wav 文件")
        if post_normalize_wav and ffmpeg_bin:
            rewav_standard_s16le_44100(out_wav, ffmpeg_bin)
        assert_wav_has_audio(out_wav)
    except BaseException:
        if out_wav.exists():
            try:
                out_wav.unlink(missing_ok=True)
            except OSError:
                pass
        raise
    finally:
        try:
            tmp_txt.unlink(missing_ok=True)
        except OSError:
            pass


def wav_to_mp3(wav: Path, mp3: Path) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("未找到 ffmpeg，无法生成 mp3")
    mp3.parent.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(
        [
            ffmpeg,
            "-y",
            "-i",
            str(wav),
            "-codec:a",
            "libmp3lame",
            "-q:a",
            "2",
            str(mp3),
        ],
        capture_output=True,
        text=True,
        timeout=300,
    )
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout or "")[:2000])


def normalize_vocab_lesson_key(raw: str) -> str:
    """用户输入 l1 / 1 / 001 → 001；m1 / m01 → m01（与 lessons_bundle words.lesson 一致）。"""
    s = raw.strip().lower().replace(" ", "")
    if not s:
        raise ValueError("课次为空")
    if s.startswith("m"):
        rest = s[1:]
        n = int(rest)
        if n <= 0:
            raise ValueError(f"无效中级课次: {raw!r}")
        return f"m{n:02d}"
    if s.startswith("l"):
        s = s[1:]
    n = int(s)
    if n <= 0:
        raise ValueError(f"无效初级课次: {raw!r}")
    return f"{n:03d}"


def folder_name_for_vocab_lesson(lesson_key: str) -> str:
    if lesson_key.startswith("m"):
        n = int(lesson_key[1:])
        return f"中级第{n:02d}课"
    n = int(lesson_key)
    return f"初级第{n:02d}课"


def text_for_vocab_entry(entry: dict) -> str:
    w = (entry.get("word") or "").strip()
    if w:
        return normalize_layout(w)
    kanji = (entry.get("kanji") or "").strip()
    kana = (entry.get("kana") or "").strip()
    kana = re.sub(r"@(\d+)$", "", kana)
    if kanji and kana:
        return normalize_layout(f"{kanji}、{kana}")
    return normalize_layout(kanji or kana)


def concat_wavs_ffmpeg(wavs: list[Path], out_wav: Path) -> None:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("拼接需要 ffmpeg，未在 PATH 中找到")
    out_wav.parent.mkdir(parents=True, exist_ok=True)
    fd, list_path = tempfile.mkstemp(prefix="piper_concat_", suffix=".txt")
    os.close(fd)
    try:
        lp = Path(list_path)
        lines = []
        for p in wavs:
            ap = p.resolve().as_posix().replace("'", r"'\''")
            lines.append(f"file '{ap}'")
        lp.write_text("\n".join(lines) + "\n", encoding="utf-8")
        r = subprocess.run(
            [
                ffmpeg,
                "-y",
                "-f",
                "concat",
                "-safe",
                "0",
                "-i",
                str(lp),
                "-c",
                "copy",
                str(out_wav.resolve()),
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=600,
        )
        if r.returncode != 0:
            raise RuntimeError((r.stderr or r.stdout or "")[:2000])
    finally:
        try:
            Path(list_path).unlink(missing_ok=True)
        except OSError:
            pass


def run_single_words_vocab(
    *,
    root: Path,
    onnx: Path,
    cfg: Path | None,
    words: list[dict],
    lesson_filter: str | None,
    do_all_lessons: bool,
    force: bool,
    use_mp3: bool,
    length_scale: float,
    noise_scale: float,
    noise_w: float | None,
    sentence_silence: float,
    merge: bool,
    post_normalize_wav: bool,
    ffmpeg_bin: str | None,
) -> int:
    """按课在 assets/single_words/<初级|中级第NN课>/ 下为每个词条生成 wav。"""
    base = root / "assets" / "single_words"
    base.mkdir(parents=True, exist_ok=True)

    by_lesson: dict[str, list[dict]] = {}
    for w in words:
        if not isinstance(w, dict):
            continue
        lk = str(w.get("lesson") or "").strip()
        if not lk:
            continue
        by_lesson.setdefault(lk, []).append(w)

    targets: list[str]
    if do_all_lessons:
        targets = sorted(by_lesson.keys(), key=lambda x: (x.startswith("m"), x))
    elif lesson_filter:
        if lesson_filter not in by_lesson:
            print(
                f"词书中没有 lesson={lesson_filter!r} 的词条（共 {len(by_lesson)} 个课号）。",
                file=sys.stderr,
            )
            return 1
        targets = [lesson_filter]
    else:
        print("请指定 --single-words-lesson 或 --single-words-all", file=sys.stderr)
        return 1

    def _lesson_sort_key(x: str) -> tuple[int, int]:
        if x.startswith("m"):
            return (1, int(x[1:]))
        return (0, int(x))

    ok = skip = fail = 0
    for lk in sorted(targets, key=_lesson_sort_key):
        entries = by_lesson[lk]
        entries.sort(key=lambda e: int(str(e.get("idx") or "0")))
        folder = base / folder_name_for_vocab_lesson(lk)
        folder.mkdir(parents=True, exist_ok=True)
        print(f"=== lesson={lk} -> {folder.name} ({len(entries)} 词) ===")
        piece_paths: list[Path] = []
        for e in entries:
            idx = str(e.get("idx") or "0").strip()
            idx_pad = f"{int(idx):04d}"
            wav = folder / f"{idx_pad}.wav"
            mp3 = folder / f"{idx_pad}.mp3"
            target = mp3 if use_mp3 else wav
            if target.exists() and not force:
                skip += 1
                piece_paths.append(target)
                continue
            text = text_for_vocab_entry(e)
            if not text.strip():
                print(f"  skip empty idx={idx}")
                skip += 1
                continue
            try:
                print(f"  {idx_pad} … ({len(text)} chars)")
                run_piper(
                    onnx=onnx,
                    config=cfg,
                    text=text,
                    out_wav=wav,
                    length_scale=length_scale,
                    noise_scale=noise_scale,
                    noise_w=noise_w,
                    sentence_silence=sentence_silence,
                    post_normalize_wav=post_normalize_wav,
                    ffmpeg_bin=ffmpeg_bin,
                )
                if use_mp3:
                    wav_to_mp3(wav, mp3)
                    if wav.exists():
                        wav.unlink()
                    piece_paths.append(mp3)
                else:
                    piece_paths.append(wav)
                ok += 1
            except Exception as ex:  # noqa: BLE001
                print(f"  FAIL idx={idx}: {ex}", file=sys.stderr)
                for p in (wav, mp3):
                    if p.exists():
                        try:
                            p.unlink()
                        except OSError:
                            pass
                fail += 1

        if merge and piece_paths:
            ext = ".mp3" if use_mp3 else ".wav"
            parts = [p for p in piece_paths if p.suffix.lower() == ext and p.exists()]
            if len(parts) < 2:
                print("  merge 跳过：有效文件不足 2 个", flush=True)
                continue
            merged = folder / f"本课全部词{ext}"
            if merged.exists() and not force:
                print(f"  已存在 {merged.name}，跳过合并（加 --force）", flush=True)
                continue
            try:
                concat_wavs_ffmpeg(parts, merged)
                print(f"  已合并 -> {merged.name}", flush=True)
            except Exception as ex:  # noqa: BLE001
                print(f"  merge FAIL: {ex}", file=sys.stderr)
                fail += 1

    print(f"single_words Done. ok={ok} skip={skip} fail={fail}")
    return 1 if fail else 0


def download_model(model_name: str, download_dir: Path) -> None:
    download_dir.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(
        [
            sys.executable,
            "-m",
            "piper",
            "--download-model",
            model_name,
            "--download-dir",
            str(download_dir),
        ],
        capture_output=True,
        text=True,
        timeout=3600,
    )
    sys.stdout.write(r.stdout or "")
    sys.stderr.write(r.stderr or "")
    if r.returncode != 0:
        raise RuntimeError(f"下载模型失败 rc={r.returncode}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Piper-plus 批量合成标日课文/单词音频")
    ap.add_argument(
        "--download-model",
        action="store_true",
        help="仅下载日语模型到 tool/.piper_models 后退出",
    )
    ap.add_argument("--force", action="store_true", help="覆盖已存在的 wav/mp3")
    ap.add_argument("--word-only", action="store_true")
    ap.add_argument("--lesson-only", action="store_true")
    ap.add_argument("--mp3", action="store_true", help="合成 wav 后用 ffmpeg 转 mp3（需本机 ffmpeg）")
    ap.add_argument(
        "--model",
        default=os.environ.get("PIPER_MODEL", "ja_JP-css10-6lang-medium"),
        help="piper 模型名（与 --download-model 一致；默认 css10 日语向）",
    )
    ap.add_argument(
        "--only",
        metavar="OKEY",
        help="仅处理该 okey（如 l1、m5），便于试跑",
    )
    ap.add_argument(
        "--model-dir",
        type=Path,
        default=None,
        help="模型目录，默认 <项目>/tool/.piper_models",
    )
    ap.add_argument("--max-chars", type=int, default=4500, help="课文文本最大字符数")
    ap.add_argument(
        "--length-scale",
        type=float,
        default=1.5,
        help="语速调节：数值越大念得越慢（约 1.2～1.8 常用；默认 1.5）。仍嫌快可试 1.7 或 2.0",
    )
    ap.add_argument("--noise-scale", type=float, default=0.5, help="日语模型常用约 0.5")
    ap.add_argument(
        "--noise-w",
        type=float,
        default=None,
        help="可选；不传则由 piper 与 config 默认处理",
    )
    ap.add_argument(
        "--sentence-silence",
        type=float,
        default=0.0,
        help="句间静音秒数（多句课文时有用）",
    )
    ap.add_argument(
        "--skip-wav-ffmpeg",
        action="store_true",
        help="跳过 ffmpeg 重编码；默认若 PATH 有 ffmpeg 则把 wav 统一为 44.1kHz s16le 以改善部分播放器",
    )
    ap.add_argument(
        "--single-words-lesson",
        metavar="课次",
        help="仅合成词书该课：1 / l1 / 001=初级，m1 / m01=中级；输出 assets/single_words/初级第01课/*.wav",
    )
    ap.add_argument(
        "--single-words-all",
        action="store_true",
        help="为词书中每个 lesson 建目录并合成全部词条（耗时很长）",
    )
    ap.add_argument(
        "--single-words-merge",
        action="store_true",
        help="每课合成后，再把该课已生成的 wav（或 mp3）拼成一条 本课全部词.wav（需 ffmpeg）",
    )
    ap.add_argument(
        "--piper-smoke-long",
        action="store_true",
        help="合成内置长日文（约数千字）到 wav 后退出，用于验证模型/本机 Piper 是否正常",
    )
    ap.add_argument(
        "--piper-smoke-out",
        type=Path,
        default=None,
        metavar="PATH",
        help="配合 --piper-smoke-long，输出 wav 路径（默认 tool/piper_long_smoke.wav）",
    )
    ap.add_argument(
        "--piper-test-phrase",
        type=str,
        default=None,
        metavar="日文",
        help="合成该短文本到 wav 后退出（默认输出 tool/piper_test_phrase.wav）；与 --piper-smoke-long 不可同用",
    )
    ap.add_argument(
        "--piper-test-out",
        type=Path,
        default=None,
        metavar="PATH",
        help="配合 --piper-test-phrase 指定输出 wav 路径",
    )
    args = ap.parse_args()

    if args.piper_smoke_long and args.piper_test_phrase:
        print(
            "不能同时使用 --piper-smoke-long 与 --piper-test-phrase。",
            file=sys.stderr,
        )
        return 1

    ffmpeg_bin = shutil.which("ffmpeg")
    post_normalize_wav = bool(ffmpeg_bin) and not args.skip_wav_ffmpeg
    if post_normalize_wav:
        print("将对 piper 输出的 wav 做 ffmpeg 标准化（44.1kHz / s16le / mono）。")
    elif args.skip_wav_ffmpeg:
        print("已按 --skip-wav-ffmpeg 跳过 wav 标准化。", flush=True)
    elif not ffmpeg_bin:
        print(
            "未找到 ffmpeg，跳过 wav 标准化；若播放器显示异常可安装 ffmpeg 后重跑。",
            flush=True,
        )

    root = project_root()
    models_dir = args.model_dir or Path(
        os.environ.get("PIPER_MODEL_DIR", str(root / "tool" / ".piper_models"))
    )

    if args.download_model:
        print(f"下载模型 {args.model!r} -> {models_dir}")
        download_model(args.model, models_dir.resolve())
        print("下载完成。")
        return 0

    onnx = find_onnx(models_dir.resolve())
    if onnx is None:
        print(
            f"未在 {models_dir} 找到 *.onnx。请先执行：\n"
            f"  python tool/synth_audio_piper.py --download-model\n"
            f"或设置 PIPER_MODEL_DIR 指向已下载模型的目录。",
            file=sys.stderr,
        )
        return 1
    cfg = config_path_for(onnx)
    print(f"使用模型: {onnx}")
    if cfg:
        print(f"配置文件: {cfg}")

    if args.piper_smoke_long:
        out_wav = (args.piper_smoke_out or (root / "tool" / "piper_long_smoke.wav")).resolve()
        base = (
            "これは音声合成モデルの安定性を確認するための長い文章です。"
            "春になり、桜の花びらが川面を流れていく様子を、多くの人が写真に収めていました。"
            "私たちは駅前の商店街を歩き、昼食にうどんを食べてから美術館へ向かう予定でした。"
        )
        long_jp = (base * 22)[:4200]
        print(f"--piper-smoke-long: 文本长度 {len(long_jp)} 字，输出 -> {out_wav}")
        try:
            run_piper(
                onnx=onnx,
                config=cfg,
                text=long_jp,
                out_wav=out_wav,
                length_scale=args.length_scale,
                noise_scale=args.noise_scale,
                noise_w=args.noise_w,
                sentence_silence=args.sentence_silence,
                post_normalize_wav=post_normalize_wav,
                ffmpeg_bin=ffmpeg_bin,
            )
        except Exception as e:  # noqa: BLE001
            print(f"FAIL: {e}", file=sys.stderr)
            return 1
        try:
            w = wave.open(str(out_wav), "rb")
            try:
                n = w.getnframes()
                rate = w.getframerate()
                ch = w.getnchannels()
            finally:
                w.close()
        except wave.Error as e:
            print(f"读出 WAV 失败: {e}", file=sys.stderr)
            return 1
        dur = n / float(rate) if rate else 0.0
        print(
            f"OK: nframes={n}, rate={rate}, ch={ch}, 约 {dur:.1f} 秒。"
            " 请用播放器试听该文件。",
            flush=True,
        )
        return 0

    if args.piper_test_phrase and args.piper_test_phrase.strip():
        phrase = args.piper_test_phrase.strip()
        out_wav = (args.piper_test_out or (root / "tool" / "piper_test_phrase.wav")).resolve()
        print(f"--piper-test-phrase: {phrase!r} -> {out_wav}")
        try:
            run_piper(
                onnx=onnx,
                config=cfg,
                text=phrase,
                out_wav=out_wav,
                length_scale=args.length_scale,
                noise_scale=args.noise_scale,
                noise_w=args.noise_w,
                sentence_silence=args.sentence_silence,
                post_normalize_wav=post_normalize_wav,
                ffmpeg_bin=ffmpeg_bin,
            )
        except Exception as e:  # noqa: BLE001
            print(f"FAIL: {e}", file=sys.stderr)
            return 1
        try:
            w = wave.open(str(out_wav), "rb")
            try:
                n = w.getnframes()
                rate = w.getframerate()
                ch = w.getnchannels()
            finally:
                w.close()
        except wave.Error as e:
            print(f"读出 WAV 失败: {e}", file=sys.stderr)
            return 1
        dur = n / float(rate) if rate else 0.0
        print(
            f"OK: nframes={n}, rate={rate}, ch={ch}, 约 {dur:.2f} 秒。"
            " 请用播放器打开上述路径试听。",
            flush=True,
        )
        return 0

    bundle = root / "assets" / "data" / "lessons_bundle.json"
    if not bundle.is_file():
        print(f"缺少数据文件: {bundle}", file=sys.stderr)
        return 1
    data = json.loads(bundle.read_text(encoding="utf-8"))

    if args.single_words_lesson or args.single_words_all:
        if args.single_words_lesson and args.single_words_all:
            print("不能同时使用 --single-words-lesson 与 --single-words-all", file=sys.stderr)
            return 1
        words = data.get("words")
        if not isinstance(words, list):
            print("lessons_bundle.json 缺少 words 数组", file=sys.stderr)
            return 1
        lf: str | None = None
        if args.single_words_lesson:
            try:
                lf = normalize_vocab_lesson_key(args.single_words_lesson)
            except ValueError as e:
                print(str(e), file=sys.stderr)
                return 1
        return run_single_words_vocab(
            root=root,
            onnx=onnx,
            cfg=cfg,
            words=words,
            lesson_filter=lf,
            do_all_lessons=bool(args.single_words_all),
            force=args.force,
            use_mp3=args.mp3,
            length_scale=args.length_scale,
            noise_scale=args.noise_scale,
            noise_w=args.noise_w,
            sentence_silence=args.sentence_silence,
            merge=args.single_words_merge,
            post_normalize_wav=post_normalize_wav,
            ffmpeg_bin=ffmpeg_bin,
        )

    level1 = data["level1"]
    level2 = data["level2"]
    keys = sorted([*level1.keys(), *level2.keys()])

    word_dir = root / "assets" / "audio" / "word"
    lesson_dir = root / "assets" / "audio" / "lesson"
    word_dir.mkdir(parents=True, exist_ok=True)
    lesson_dir.mkdir(parents=True, exist_ok=True)

    include_word = not args.lesson_only
    include_lesson = not args.word_only
    ok = skip = fail = 0

    for okey in keys:
        if args.only and okey != args.only:
            continue
        obj = lesson_entry(level1, level2, okey)
        for kind in ("word", "lesson"):
            if kind == "word" and not include_word:
                continue
            if kind == "lesson" and not include_lesson:
                continue
            out_dir = word_dir if kind == "word" else lesson_dir
            wav = out_dir / f"{okey}.wav"
            mp3 = out_dir / f"{okey}.mp3"
            target = mp3 if args.mp3 else wav
            if target.exists() and not args.force:
                skip += 1
                continue
            try:
                if kind == "word":
                    text = word_text_primary(obj, okey)
                else:
                    text = truncate(lesson_text_long(obj, okey), args.max_chars)
                if not text.strip():
                    print(f"skip empty {kind}/{okey}")
                    skip += 1
                    continue
                print(f"{kind}/{okey}.wav … ({len(text)} chars)")
                run_piper(
                    onnx=onnx,
                    config=cfg,
                    text=text,
                    out_wav=wav,
                    length_scale=args.length_scale,
                    noise_scale=args.noise_scale,
                    noise_w=args.noise_w,
                    sentence_silence=args.sentence_silence,
                    post_normalize_wav=post_normalize_wav,
                    ffmpeg_bin=ffmpeg_bin,
                )
                if args.mp3:
                    wav_to_mp3(wav, mp3)
                    if wav.exists():
                        wav.unlink()
                ok += 1
            except Exception as e:  # noqa: BLE001
                print(f"FAIL {kind}/{okey}: {e}", file=sys.stderr)
                for p in (wav, mp3):
                    if p.exists():
                        try:
                            p.unlink()
                        except OSError:
                            pass
                fail += 1

    print(f"Done. ok={ok} skip={skip} fail={fail}")
    return 1 if fail else 0


if __name__ == "__main__":
    raise SystemExit(main())
