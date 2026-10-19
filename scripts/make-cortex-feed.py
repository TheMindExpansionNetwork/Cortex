#!/usr/bin/env python3
"""Build the signed Cortex release feed (cortex-feed.json + .sig) from a Terminal archive and engine packages.

    python scripts/make-cortex-feed.py --out FEED --terminal cortex-control-*.tar.gz \
        --engine components/engine/0.1.45-linux-x86_64-cuda-cuda13 [--engine ...] \
        --key ~/.cortex-keys/cortex-feed-private.pem [--sequence N] [--expires-days 90]

    # once, on the owner's machine, OUTSIDE any git checkout:
    python scripts/make-cortex-feed.py --generate-key ~/.cortex-keys/cortex-feed-private.pem

What it writes into FEED (the folder a person hosts, or the assets of the GitHub release):
    cortex-feed.json + .sig       the signed feed (Ed25519 over the exact file bytes; see cortex_control/feed.py)
    control/*, engine/*           the Terminal (a "control" package) and each engine package, archived
    install.sh, install.ps1       the one-line installers with this feed's address filled in
    update-trust.json             the public half of the key: CORTEX_UPDATE_TRUSTED_KEYS=<this file> lets a
                                  build trust the feed before the key ships inside cortex_control/update_keys.json

Entries are named `cortex-*` (cortex-engine-<version>-<platform>-<backend>[-<variant>].tar.gz,
cortex-control-<version>-<platform>.tar.gz) by packaging/feed_tool.py, and the feed's release address is
https://github.com/TheMindExpansionNetwork/Cortex/releases/latest/download (assets are flat, so the feed's
`url` members are plain file names). The feed schema is exactly what cortex_control/feed.py parses and what
`cortex update` verifies: the signature covers the file's bytes; every archive and manifest hash is inside.

The feed file is named cortex-feed.json (REBRAND NOTE: cortex_control/feed.py still sets FEED_NAME =
"strata-feed.json" and cortex_cli/update_cmd.py's DEFAULT_FEED still points at the Strata URL - the owner of
those paths renames them; until then set CORTEX_UPDATE_FEED to the cortex-feed.json URL for a local check).

The private key must live OUTSIDE any git checkout (the owner keeps it offline; default here refuses to
generate or read one inside a checkout). Signing a release feed with a throwaway key would quietly break
every installed PC, so --key or --generate-key is required - unlike packaging/make_local_feed.py, which
mints a test key for its throwaway local feed.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
#: The release address baked into the feed's relative URLs and into install.sh / install.ps1 (P5b).
RELEASE_FEED = "https://github.com/TheMindExpansionNetwork/Cortex/releases/latest/download"
#: What the upstream installers still carry, so they can be pointed at this feed by a plain replace.
UPSTREAM_FEED = "https://github.com/Niko1221/Strata/releases/latest/download"
FEED_FILE = "cortex-feed.json"

sys.path.insert(0, str(ROOT / "packaging"))
sys.path.insert(0, str(ROOT))

import feed_tool as ft  # noqa: E402
from cortex_control import feed as feedmod  # noqa: E402
from cortex_control import signing  # noqa: E402


def extract_terminal(archive: Path, into: Path) -> Path:
    """Unpack a terminal archive; returns the folder that holds python/ and cortex.py."""
    if archive.name.endswith(".zip"):
        with zipfile.ZipFile(archive) as zf:
            zf.extractall(into)
    else:
        with tarfile.open(archive) as tf:
            try:
                tf.extractall(into, filter="data")
            except TypeError:                       # Python before 3.12 (a Mac's system 3.9): no extraction filters; the archive is our own
                tf.extractall(into)
    (inner,) = [p for p in into.iterdir() if p.is_dir()]
    return inner


def generate_key(path: Path) -> dict:
    """A NEW Ed25519 feed key as cortex_control/signing.py defines it: the file holds the seed (the secret),
    the public half and its key_id (first 8 bytes of SHA-256 of the public key). Refuses to overwrite and to
    live inside a git checkout; chmod 0600. The public half lands beside it as <name>.pub.json."""
    path = path.resolve()
    if ft._inside_git(path):
        raise SystemExit(f"{path} is inside a git checkout; a private key must not be where it can be committed. "
                         "Use a folder outside the repository (e.g. ~/.cortex-keys).")
    if path.exists():
        raise SystemExit(f"{path} already exists; refusing to overwrite a key")
    path.parent.mkdir(parents=True, exist_ok=True)
    key = signing.generate_key()
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        json.dump(key, stream, indent=1)
        stream.write("\n")
    os.chmod(path, 0o600)
    (path.parent / (path.name + ".pub.json")).write_text(
        json.dumps({"schema_version": 1, "keys": [signing.public_part(key)]}, indent=1) + "\n", encoding="utf-8")
    return key


def previous_sequence(out: Path) -> int | None:
    """The sequence of an earlier cortex-feed.json in --out, so the next feed never goes backwards."""
    path = out / FEED_FILE
    try:
        return int(json.loads(path.read_text(encoding="utf-8-sig"))["sequence"])
    except (OSError, ValueError, KeyError, TypeError):
        return None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=None, help="the release folder (cortex-feed.json, engine/, control/)")
    ap.add_argument("--terminal", type=Path, action="append", default=[], help="a terminal archive (.tar.gz or .zip); repeat per platform")
    ap.add_argument("--engine", type=Path, action="append", default=[], help="an engine package folder (with engine-component.json); repeat")
    ap.add_argument("--key", type=Path, default=None, help="the secret feed key file (alg ed25519 + seed; made by --generate-key)")
    ap.add_argument("--generate-key", type=Path, default=None, metavar="PATH",
                    help="generate a NEW key at PATH (+ PATH.pub.json) instead of signing; no feed is built")
    ap.add_argument("--url", default=RELEASE_FEED, help="the address this feed will be served at (baked into install.sh/.ps1)")
    ap.add_argument("--url-prefix", default="", help='where the archives sit relative to the feed ("" = flat, GitHub release assets)')
    ap.add_argument("--sequence", type=int, default=None, help="the feed's sequence (default: the previous feed's + 1, else 1)")
    ap.add_argument("--channel", default="stable")
    ap.add_argument("--expires-days", type=int, default=None)
    ap.add_argument("--version", default=None, help="control version label (default: from the first terminal archive's VERSION)")
    a = ap.parse_args(argv)

    if a.generate_key:
        key = generate_key(a.generate_key)
        print(f"key written to {a.generate_key} (SECRET, chmod 600, keep it offline and backed up)")
        print(f"public half: {a.generate_key}.pub.json")
        print("key_id:", key["key_id"])
        print("public :", key["public"])
        print("next: put this entry into cortex_control/update_keys.json (keys) in the first signed-release commit;")
        print("      until then: CORTEX_UPDATE_TRUSTED_KEYS=<cortex_control/cortex_feed_public_key.json>")
        return 0

    if not (a.terminal or a.engine):
        ap.error("nothing to publish: give --terminal and/or --engine")
    if not a.out:
        ap.error("--out is required to build a feed (it is not needed for --generate-key alone)")
    if not a.key:
        ap.error("signing a release feed needs --key (or --generate-key PATH to make the key once)")

    key = ft._load_key(a.key.resolve())
    base = a.url.rstrip("/")
    out = a.out.resolve()
    if ft._inside_git(out / FEED_FILE):
        print(f"note: {out} is inside a git checkout; fine for a local test feed, never host the real one from here",
              file=sys.stderr)

    version = a.version
    with tempfile.TemporaryDirectory(prefix="cortex-feed-") as tmp:
        tmpdir = Path(tmp)
        for n, term in enumerate(a.terminal):
            work = tmpdir / f"t{n}"
            work.mkdir()
            folder = extract_terminal(term.resolve(), work)
            v = version or (folder / "VERSION").read_text(encoding="utf-8").strip()
            version = v
            platform = ("windows-x86_64" if (folder / "python" / "python.exe").exists() else
                        "macos-arm64" if ("darwin" in term.name or "macos" in term.name) else "linux-x86_64")
            fmt = "zip" if platform.startswith("windows") else "tar.gz"
            entry = ft.pack_control(folder, out / "control", version=v, platform=platform, fmt=fmt, url_prefix=a.url_prefix)
            print(f"control {platform} {v}: {entry['size'] // 1048576} MB")
        for n, pkg in enumerate(a.engine):
            copy = tmpdir / f"e{n}" / pkg.name
            shutil.copytree(pkg, copy, symlinks=True)
            ft.sign_package(copy, key)
            entry = ft.pack_engine(copy, out / "engine", url_prefix=a.url_prefix)
            print(f"engine {entry['platform']}-{entry['backend']} {entry['variant'] or '-'} {entry['version']}: {entry['size'] // 1048576} MB")
            shutil.rmtree(copy.parent, ignore_errors=True)

    sequence = a.sequence
    if sequence is None:
        sequence = (previous_sequence(out) or 0) + 1
    staging = out.parent / f".{out.name}.build"
    shutil.rmtree(staging, ignore_errors=True)
    staging.mkdir(parents=True)
    if a.engine:
        shutil.move(str(out / "engine"), str(staging / "engine"))
    if a.terminal:
        shutil.move(str(out / "control"), str(staging / "control"))
    # build_feed writes whatever cortex_control/feed.py names the feed; it must be cortex-feed.json here
    ft.build_feed(staging, key=key, sequence=sequence, channel=a.channel,
                  engine_dir=staging / "engine" if a.engine else None,
                  control_dir=staging / "control" if a.terminal else None,
                  expires_days=a.expires_days)
    built = staging / feedmod.FEED_NAME
    sig = staging / (feedmod.FEED_NAME + feedmod.SIGNATURE_SUFFIX)
    if built.name != FEED_FILE:                  # cortex_control/feed.py may still name it strata-feed.json
        built = built.rename(staging / FEED_FILE)
    sig.rename(staging / (FEED_FILE + feedmod.SIGNATURE_SUFFIX))
    shutil.rmtree(out, ignore_errors=True)
    staging.rename(out)

    for name in ("install.sh", "install.ps1"):
        text = (ROOT / "packaging" / name).read_text(encoding="utf-8").replace(UPSTREAM_FEED, base)
        (out / name).write_text(text, encoding="utf-8", newline="\n" if name.endswith(".sh") else None)
    (out / "update-trust.json").write_text(
        json.dumps({"schema_version": 1, "keys": [signing.public_part(key)]}, indent=1) + "\n", encoding="utf-8")

    # the parse is the last check: a feed this script makes must be a feed Control accepts (same guard as feed_tool.build_feed)
    payload = (out / FEED_FILE).read_bytes()
    signature = (out / (FEED_FILE + feedmod.SIGNATURE_SUFFIX)).read_text(encoding="utf-8")
    loaded = feedmod.verify_and_parse(payload, signature.encode(), source=str(out / FEED_FILE),
                                      trusted={key["key_id"]: __import__("base64").b64decode(key["public"])})
    engine_count = len(loaded.engine)
    control_count = len(loaded.control)
    print(f"feed written to {out / FEED_FILE} (+ .sig); sequence {loaded.sequence}, channel {loaded.channel}, "
          f"signed by key {loaded.key_id}; {engine_count} engine packages, {control_count} control packages")
    print(f"  trust it:   CORTEX_UPDATE_TRUSTED_KEYS={out / 'update-trust.json'} "
          f"(one-line update: CORTEX_UPDATE_FEED={base}/{FEED_FILE})")
    if base.startswith(("http://127.0.0.1", "http://localhost")):
        print(f"  serve it:   python -m http.server {base.rsplit(':', 1)[-1]} --bind 127.0.0.1 --directory {out}")
    print(f"  publish:    upload everything in {out} as the GitHub release assets of TheMindExpansionNetwork/Cortex")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
