#!/usr/bin/env python3
"""JSON CLI boundary for Adaptation.Providers.LoRA.

Wraps the Vast.ai dark-factory LoRA pipeline (Kohya_ss / AI Toolkit) behind a
deterministic --output-format json contract. Orchestration never shells out to
a training script directly; it calls these entry points.

    vastai-lora-train --dataset PATH --base-model NAME [--config PATH] --output-format json
    vastai-lora-eval --artifact URI --suites suite1,suite2 --output-format json

Backend (production):
    VASTAI_LORA_TRAIN_BACKEND  command that actually trains
    VASTAI_LORA_EVAL_BACKEND   command that actually evaluates
    VASTAI_LORA_ARTIFACT_URI   used if the backend does not print JSON

Wiring / CI without GPUs:
    --stub or ADAPTATION_CLI_STUB=1
    ADAPTATION_CLI_EVAL_SCORE  (default 0.8)
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1


def emit(payload: dict[str, Any], exit_code: int = 0) -> int:
    payload.setdefault("schema_version", SCHEMA_VERSION)
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    return exit_code


def fail(reason: str, exit_code: int = 1) -> int:
    return emit({"ok": False, "error": reason}, exit_code)


def last_json_object(text: str) -> dict[str, Any] | None:
    for line in reversed(text.splitlines()):
        line = line.strip()
        if not line:
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            return value
    return None


def run_backend(backend: str, extra_args: list[str]) -> subprocess.CompletedProcess[str]:
    cmd = shlex.split(backend) + extra_args
    return subprocess.run(cmd, check=False, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)


def require_json_format(value: str) -> str:
    if value != "json":
        raise argparse.ArgumentTypeError("--output-format must be json")
    return value


def stub_requested(args: argparse.Namespace) -> bool:
    if getattr(args, "stub", False):
        return True
    flag = os.environ.get("ADAPTATION_CLI_STUB", "")
    return flag.lower() in {"1", "true", "yes"}


def train(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="vastai-lora-train")
    parser.add_argument("--dataset", required=True)
    parser.add_argument("--base-model", required=True)
    parser.add_argument("--config")
    parser.add_argument("--output-format", required=True, type=require_json_format)
    parser.add_argument(
        "--stub",
        action="store_true",
        help="Emit contract JSON without invoking a GPU backend",
    )
    args = parser.parse_args(argv)

    dataset = Path(args.dataset)
    if not dataset.exists() and not stub_requested(args):
        return fail(f"dataset not found: {args.dataset}")

    if stub_requested(args):
        version = f"stub-{abs(hash(args.dataset + args.base_model)) % 10_000_000:07d}"
        artifact = f"file://{dataset.with_suffix('.safetensors')}"
        return emit(
            {
                "ok": True,
                "artifact_uri": artifact,
                "version": version,
                "metrics": {"train_loss": 0.0, "stub": True},
                "provider": "lora",
            }
        )

    backend = os.environ.get("VASTAI_LORA_TRAIN_BACKEND", "").strip()
    if not backend:
        return fail(
            "backend not configured: set VASTAI_LORA_TRAIN_BACKEND or pass --stub"
        )

    passthrough = [
        "--dataset",
        args.dataset,
        "--base-model",
        args.base_model,
        "--output-format",
        "json",
    ]
    if args.config:
        passthrough.extend(["--config", args.config])

    completed = run_backend(backend, passthrough)
    payload = last_json_object(completed.stdout or "")
    if payload is not None:
        payload.setdefault("schema_version", SCHEMA_VERSION)
        if completed.returncode != 0 and payload.get("ok") is not False:
            payload = {
                "schema_version": SCHEMA_VERSION,
                "ok": False,
                "error": payload.get("error") or f"backend exit {completed.returncode}",
            }
        return emit(payload, 0 if payload.get("ok") else completed.returncode or 1)

    if completed.returncode != 0:
        snippet = (completed.stdout or "")[-500:]
        return fail(f"backend exit {completed.returncode}: {snippet}")

    artifact = os.environ.get("VASTAI_LORA_ARTIFACT_URI", "").strip()
    version = os.environ.get("VASTAI_LORA_VERSION", "").strip()
    if not artifact or not version:
        return fail(
            "backend printed no JSON; set VASTAI_LORA_ARTIFACT_URI and VASTAI_LORA_VERSION"
        )

    return emit(
        {
            "ok": True,
            "artifact_uri": artifact,
            "version": version,
            "metrics": {},
            "provider": "lora",
        }
    )


def eval_cmd(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="vastai-lora-eval")
    parser.add_argument("--artifact", required=True)
    parser.add_argument("--suites", required=True, help="comma-separated suite names")
    parser.add_argument("--output-format", required=True, type=require_json_format)
    parser.add_argument("--stub", action="store_true")
    args = parser.parse_args(argv)

    suites = [name for name in args.suites.split(",") if name]
    if not suites:
        return fail("no suites given")

    if stub_requested(args):
        try:
            score = float(os.environ.get("ADAPTATION_CLI_EVAL_SCORE", "0.8"))
        except ValueError:
            return fail("ADAPTATION_CLI_EVAL_SCORE must be a number")
        return emit(
            {
                "ok": True,
                "suites": {
                    suite: {"score": score, "passed": score >= 0.5, "stub": True}
                    for suite in suites
                },
            }
        )

    backend = os.environ.get("VASTAI_LORA_EVAL_BACKEND", "").strip()
    if not backend:
        return fail("backend not configured: set VASTAI_LORA_EVAL_BACKEND or pass --stub")

    completed = run_backend(
        backend,
        [
            "--artifact",
            args.artifact,
            "--suites",
            args.suites,
            "--output-format",
            "json",
        ],
    )
    payload = last_json_object(completed.stdout or "")
    if payload is not None:
        payload.setdefault("schema_version", SCHEMA_VERSION)
        return emit(payload, 0 if payload.get("ok") else completed.returncode or 1)

    if completed.returncode != 0:
        snippet = (completed.stdout or "")[-500:]
        return fail(f"backend exit {completed.returncode}: {snippet}")

    return fail("backend printed no eval JSON")


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    prog = Path(sys.argv[0]).name

    if prog.endswith("vastai-lora-eval") or (argv and argv[0] == "eval"):
        if argv and argv[0] == "eval":
            argv = argv[1:]
        return eval_cmd(argv)

    if prog.endswith("vastai-lora-train") or (argv and argv[0] == "train"):
        if argv and argv[0] == "train":
            argv = argv[1:]
        return train(argv)

    sys.stderr.write("usage: vastai-lora-train | vastai-lora-eval | vastai_lora.py train|eval\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
