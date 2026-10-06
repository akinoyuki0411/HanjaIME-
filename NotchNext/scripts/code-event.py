#!/usr/bin/env python3
"""Publish one explicit local task event; no account or transcript access."""
import argparse, datetime, json, os, pathlib, tempfile, uuid
p = argparse.ArgumentParser()
p.add_argument('--title', required=True)
p.add_argument('--phase', choices=['thinking', 'working', 'completed', 'failed'], required=True)
p.add_argument('--progress', type=float)
p.add_argument('--id', default=None)
p.add_argument('--output', type=pathlib.Path, default=pathlib.Path.home()/'Library/Application Support/HanjiME/code-activity.json')
a = p.parse_args()
if len(a.title) > 200 or (a.progress is not None and not 0 <= a.progress <= 1): p.error('Title max 200 characters; progress must be 0...1')
payload = dict(id=a.id or str(uuid.uuid4()), title=a.title, phase=a.phase, progress=a.progress, date=datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))
a.output.parent.mkdir(parents=True, exist_ok=True)
fd, tmp = tempfile.mkstemp(dir=a.output.parent)
try:
    with os.fdopen(fd, 'w') as f: json.dump(payload, f, ensure_ascii=False)
    os.replace(tmp, a.output)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
print(a.output)
