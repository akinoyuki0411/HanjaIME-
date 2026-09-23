#!/usr/bin/env python3
"""Apply a hash-verified all-or-nothing patch to the supported Gureum snapshot."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parent
PIN = '5bdc5dc3df93d5a3aa61ad1df928d76bc903054b'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def safe_path(repo, name):
    rel = Path(name)
    if rel.is_absolute() or '..' in rel.parts:
        raise RuntimeError('Unsafe patch path: ' + name)
    path = repo / rel
    if path.is_symlink() or not path.resolve().is_relative_to(repo):
        raise RuntimeError('Refusing a symlink/escaped target: ' + name)
    if path.exists() and not path.is_file():
        raise RuntimeError('Target is not a file: ' + name)
    return path


def apply(repo, check_only=False):
    repo = repo.resolve()
    manifest = json.loads((ROOT/'patches/manifest.json').read_text())
    patch = ROOT/'patches/gureum.patch'
    if digest(patch) != manifest['patch_sha256']:
        raise RuntimeError('Patch checksum mismatch; package is incomplete or modified.')
    states = []
    for item in manifest['files']:
        path = safe_path(repo, item['path'])
        actual = digest(path)
        if actual == item['after']:
            states.append('after')
        elif actual == item['before']:
            states.append('before')
        else:
            raise RuntimeError('Unexpected user/source changes; nothing written: '+item['path'])
    if all(state == 'after' for state in states):
        print('HanjaIME patch already applied; every output checksum matches.')
        return
    if not all(state == 'before' for state in states):
        raise RuntimeError('Mixed/partial patch state; nothing written. Use the saved source backup.')
    revision = subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip()
    if revision != PIN:
        raise RuntimeError('Unsupported Gureum commit: '+revision+'; expected '+PIN)
    subprocess.run(['git','apply','--check',str(patch)],cwd=repo,check=True)
    if check_only:
        print('All original checksums and git apply --check passed; no files changed.')
        return
    backup = repo/'.hanjaime-backups'/(dt.datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:8])
    backup.mkdir(parents=True)
    (backup/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    for item in manifest['files']:
        if item['before'] is not None:
            dest = backup/item['path']; dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(repo/item['path'],dest)
    try:
        subprocess.run(['git','apply',str(patch)],cwd=repo,check=True)
        for item in manifest['files']:
            if digest(repo/item['path']) != item['after']:
                raise RuntimeError('Post-patch verification failed: '+item['path'])
    except BaseException:
        for item in manifest['files']:
            target = repo/item['path']
            if item['before'] is None:
                target.unlink(missing_ok=True)
            else:
                shutil.copy2(backup/item['path'],target)
        raise
    # Local backup never enters commits or exported user data.
    exclude=repo/'.git/info/exclude'
    if exclude.parent.is_dir():
        with exclude.open('a') as f: f.write('\n.hanjaime-backups/\n')
    print('HanjaIME patch applied and verified. Source backup: '+str(backup))


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('repo',type=Path)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    try:
        apply(args.repo,args.check)
    except (RuntimeError,OSError,subprocess.SubprocessError) as error:
        print('ERROR:',error,file=sys.stderr)
        return 1
    return 0

if __name__=='__main__':
    sys.exit(main())
