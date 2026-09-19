#!/usr/bin/env python3
"""Hardware UVC image controls with a software eq fallback."""
from __future__ import annotations

import json
import re
import subprocess
import sys

KEYS = ("brightness", "contrast", "saturation")


def load_config(path: str) -> dict:
    defaults = {k: 0 for k in KEYS}
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        data = {}
    if not isinstance(data, dict):
        data = {}
    out = dict(defaults)
    for key in KEYS:
        try:
            out[key] = int(data.get(key, 0) or 0)
        except (TypeError, ValueError):
            out[key] = 0
        out[key] = max(-100, min(100, out[key]))
    return out


def list_ctrls(device: str) -> dict:
    try:
        raw = subprocess.check_output(
            ["v4l2-ctl", "-d", device, "--list-ctrls"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        raw = ""
    found = {}
    for line in raw.splitlines():
        m = re.search(
            r"^\s*([A-Za-z0-9_]+)\s+0x[0-9a-fA-F]+\s+\((\w+)\)\s*:\s*(.*)$",
            line,
        )
        if not m:
            continue
        name, kind, rest = m.group(1), m.group(2), m.group(3)
        if name not in KEYS or kind != "int":
            continue
        fields = dict(re.findall(r"(min|max|step|default|value)=(-?\d+)", rest))
        if "min" not in fields or "max" not in fields:
            continue
        found[name] = {
            "min": int(fields["min"]),
            "max": int(fields["max"]),
            "step": int(fields.get("step", 1) or 1),
            "default": int(fields.get("default", fields.get("value", 0))),
            "value": int(fields.get("value", fields.get("default", 0))),
        }
    return found


def backends(device: str) -> dict:
    hw = list_ctrls(device)
    return {key: ("hw" if key in hw else "sw") for key in KEYS}


def ui_to_hw(ctrl: dict, ui: int) -> int:
    ui = max(-100, min(100, int(ui)))
    default = ctrl["default"]
    lo, hi = ctrl["min"], ctrl["max"]
    if ui == 0:
        return default
    if ui > 0:
        raw = default + (hi - default) * ui / 100.0
    else:
        raw = default + (default - lo) * ui / 100.0
    step = max(1, ctrl.get("step", 1))
    snapped = lo + round((raw - lo) / step) * step
    return int(max(lo, min(hi, snapped)))


def eq_filter(cfg: dict, device: str) -> str:
    hw = list_ctrls(device)
    parts = []
    b = int(cfg.get("brightness", 0) or 0)
    c = int(cfg.get("contrast", 0) or 0)
    s = int(cfg.get("saturation", 0) or 0)
    if "brightness" not in hw and b:
        parts.append(f"brightness={b / 100.0:.4f}")
    if "contrast" not in hw and c:
        parts.append(f"contrast={max(0.01, 1.0 + c / 100.0):.4f}")
    if "saturation" not in hw and s:
        parts.append(f"saturation={max(0.0, 1.0 + s / 100.0):.4f}")
    if not parts:
        return ""
    return "eq=" + ":".join(parts)


def apply_hw(device: str, cfg: dict) -> dict:
    hw = list_ctrls(device)
    sets = []
    for key in KEYS:
        if key not in hw:
            continue
        sets.append(f"{key}={ui_to_hw(hw[key], cfg.get(key, 0))}")
    if sets:
        subprocess.run(
            ["v4l2-ctl", "-d", device, "--set-ctrl=" + ",".join(sets)],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    return backends(device)


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: image.py ctrls|apply|eq-filter ...", file=sys.stderr)
        return 2
    cmd = sys.argv[1]
    if cmd == "ctrls":
        device = sys.argv[2] if len(sys.argv) > 2 else "/dev/video0"
        hw = list_ctrls(device)
        out = {"device": device, "controls": {}}
        for key in KEYS:
            if key in hw:
                item = dict(hw[key])
                item["backend"] = "hw"
            else:
                item = {"backend": "sw"}
            out["controls"][key] = item
        print(json.dumps(out))
        return 0
    if cmd == "apply":
        device = sys.argv[2]
        cfg_path = sys.argv[3]
        cfg = load_config(cfg_path)
        if len(sys.argv) >= 7:
            for key, raw in zip(KEYS, sys.argv[4:7]):
                try:
                    cfg[key] = max(-100, min(100, int(raw)))
                except ValueError:
                    pass
            try:
                with open(cfg_path, encoding="utf-8") as fh:
                    data = json.load(fh)
            except Exception:
                data = {}
            if not isinstance(data, dict):
                data = {}
            data.update(cfg)
            with open(cfg_path, "w", encoding="utf-8") as fh:
                json.dump(data, fh, indent=2)
                fh.write("\n")
        used = apply_hw(device, cfg)
        print(json.dumps({"ok": True, "backends": used, "values": cfg}))
        return 0
    if cmd == "apply-live":
        device = sys.argv[2]
        cfg = {key: 0 for key in KEYS}
        if len(sys.argv) >= 6:
            for key, raw in zip(KEYS, sys.argv[3:6]):
                try:
                    cfg[key] = max(-100, min(100, int(raw)))
                except ValueError:
                    pass
        used = apply_hw(device, cfg)
        print(json.dumps({"ok": True, "backends": used, "values": cfg}))
        return 0
    if cmd == "eq-filter":
        cfg = load_config(sys.argv[2])
        device = sys.argv[3] if len(sys.argv) > 3 else "/dev/video0"
        print(eq_filter(cfg, device), end="")
        return 0
    print("unknown command", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
