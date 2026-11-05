#!/usr/bin/env python3
"""Smoke-test the release app, including its real startup refresh and popover.

Only processes created by this script are terminated. Existing Sumbar instances,
preferences and the cache are left in place. Run on a Mac with a desktop session.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument('app', type=Path)
parser.add_argument('--seconds', type=float, default=30)
args = parser.parse_args()
if args.seconds <= 0:
    parser.error('--seconds must be positive')
binary = args.app.resolve() / 'Contents' / 'MacOS' / 'Sumbar'
if not binary.is_file():
    parser.error(f'App executable not found: {binary}')

for mode, flags in [('normal', []), ('popover', ['--preview'])]:
    with tempfile.TemporaryFile() as log:
        started = time.monotonic()
        child = subprocess.Popen([str(binary), *flags], stdout=log, stderr=log)
        try:
            try:
                code = child.wait(timeout=args.seconds)
            except subprocess.TimeoutExpired:
                print(json.dumps({'mode': mode, 'alive_after_seconds': round(time.monotonic() - started, 1), 'pid': child.pid}), flush=True)
            else:
                log.seek(0)
                print(log.read().decode(errors='replace'))
                raise SystemExit(f'{mode} launch exited early with code {code}')
        finally:
            if child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=5)
print('Both release launch modes remained running.', flush=True)
