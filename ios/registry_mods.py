#!/usr/bin/env python3
"""Horizon's registry (horizon-rust/horizon-mods) built into the iOS app: what works on an iPhone, at build time.

    python3 ios/registry_mods.py --registry REGISTRY_CLONE --out ios/build/registry [--check-target aarch64-apple-ios]

An iPhone can't compile, so the native (Rust) mods are compiled into the game here, as the launcher builds them on a
computer:
  - every native mod's newest version that isn't taken down, applied with horizon-mixins on this workspace; a mod it
    refuses is left out (with the mods that need it), as the launcher leaves it out;
  - then `cargo check` for the iPhone with Horizon's `mods` feature, leaving out the mods the errors are in, round by
    round; when the errors are in no mod's code, no native mod is built in;
  - mods with an API package (the launcher stages those as crates) are left out, as the registry's own check does.
The mods that are left are written into this workspace (horizon-mixins' output over the source), and their content
(assets, data) into OUT/native-content/<id>/, which goes beside the game in Horizon.app.

Content mods without code (`.hmod`), resource packs and Horizon shader packs (`.hshader`) are downloaded, checked
against the registry's SHA-256, and put into OUT/Registry/game/{horizon-mods,resourcepacks,shaderpacks}/: the
launcher copies them into the game folder once. OUT/Registry/registry.json lists what went in and what was left out,
and why. Both OUT folders go into Horizon.app as they are (ios/project.yml).

It reads horizon-mods' own scripts (scripts/native_compat.py, native_trace.py) from the clone for horizon-mixins and
the error tracing, so it applies and traces exactly as the registry's checks do.
"""
import argparse
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tomllib
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = "26.3"
RELEASES = "https://github.com/horizon-rust/horizon-mods/releases/download"
COMPILE_ROUNDS = 6
CONTENT_FOLDERS = {"mod": "horizon-mods", "resourcepack": "resourcepacks", "shader": "shaderpacks"}


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def entries(registry):
    """Each registry project with its newest version for this game that isn't taken down: [(entry, version)]."""
    revoked = tomllib.loads((registry / "revoked.toml").read_text()).get("revoked", [])
    files = {r["sha256"] for r in revoked if r.get("sha256")}
    ids = {r["id"] for r in revoked if not r.get("sha256")}
    found = []
    for path in sorted((registry / "mods").glob("*.toml")):
        entry = tomllib.loads(path.read_text())
        if entry["id"] in ids:
            continue
        versions = [v for v in entry.get("versions", []) if v.get("game") == GAME and v["sha256"] not in files]
        if versions:
            found.append((entry, max(versions, key=lambda v: v.get("published", ""))))
    return found


def download(nc, entry, version):
    return nc.download(f"{RELEASES}/{entry['id']}-{version['version']}/{version['file']}", version["sha256"])


def content(nc, found, out, report):
    """The content mods without code, resource packs and Horizon shader packs, into OUT/game/."""
    for entry, version in found:
        kind = entry.get("kind", "mod")
        if kind not in CONTENT_FOLDERS:
            continue
        name = f"{entry['id']} {version['version']}"
        try:
            data = download(nc, entry, version)
        except Exception as e:  # noqa: BLE001 (a file that can't be fetched is left out, not the build)
            report["left_out"].append({"id": entry["id"], "kind": kind, "why": f"download: {e}"})
            continue
        if kind == "mod":
            # Code (any capability but `registries`) doesn't run in this game any more (mod_registry::needs_port).
            try:
                manifest = tomllib.loads(zipfile.ZipFile(io.BytesIO(data)).read("horizon-mod.toml").decode())
            except Exception as e:  # noqa: BLE001
                report["left_out"].append({"id": entry["id"], "kind": kind, "why": f"unreadable: {e}"})
                continue
            caps = manifest.get("capabilities", manifest.get("mod", {}).get("capabilities", []))
            if any(c != "registries" for c in caps):
                report["left_out"].append({"id": entry["id"], "kind": kind, "why": "has code"})
                continue
        folder = out / "Registry" / "game" / CONTENT_FOLDERS[kind]
        folder.mkdir(parents=True, exist_ok=True)
        (folder / version["file"]).write_bytes(data)
        report["content"].append({"id": entry["id"], "name": entry.get("name", entry["id"]), "kind": kind,
                                  "version": version["version"], "file": version["file"]})
        log(f"  content: {name} ({kind})")


def pristine(tree, into):
    """This commit's tracked files, without links (horizon-mixins refuses them), as the registry's checks get
    Horizon's source from GitHub's archive."""
    shutil.rmtree(into, ignore_errors=True)
    into.mkdir(parents=True)
    archive = subprocess.run(["git", "-C", str(tree), "archive", "--format=tar", "HEAD"],
                             check=True, capture_output=True).stdout
    subprocess.run(["tar", "-x", "-C", str(into)], input=archive, check=True)
    for path in into.rglob("*"):
        if path.is_symlink():
            path.unlink()
    # horizon-mixins checks a mod's pin against this file, else `git rev-parse HEAD` of the folder (which, here,
    # would be another repository's).
    revision = subprocess.run(["git", "-C", str(tree), "rev-parse", "HEAD"], check=True, capture_output=True,
                              text=True).stdout.strip()
    (into / ".horizon-revision").write_text(revision)
    return into


def has_mods_feature(tree):
    """Whether this Horizon has a `mods` feature to build native mods with (older ones did)."""
    client = tomllib.loads((Path(tree) / "crates/horizon-client/Cargo.toml").read_text())
    return "mods" in client.get("features", {})


def check(nc, stage, target, features):
    """`cargo check` of the game in `stage`, in nc.WORK/check (where the registry's tracer reads the spans): None
    when it compiles, else its errors."""
    work = nc.WORK / "check"
    work.mkdir(parents=True, exist_ok=True)
    subprocess.run(["rsync", "-a", "--checksum", "--delete", f"{stage}/", f"{work}/"], check=True)
    if target:
        command = ["cargo", "check", "--message-format=json", "--profile", "fast", "-p", "horizon-ios",
                   "--target", target]
    else:
        command = ["cargo", "check", "--message-format=json", "-p", "horizon-client", "--bin", "horizon-client"]
    if features and has_mods_feature(work):
        command += ["--features", "horizon-client/mods"]
    env = dict(os.environ, CARGO_TARGET_DIR=str(nc.WORK / "cargo"))
    run = subprocess.run(command, cwd=work, env=env, capture_output=True, text=True)
    if run.returncode == 0:
        return None
    found = nc.native_trace.errors(run.stdout)
    for e in found[:6]:
        log(e["rendered"].rstrip())
    return found or [{"code": "E_CARGO", "message": run.stderr[-2000:], "rendered": run.stderr[-2000:], "spans": []}]


def native(nc, found, tree, out, report, target, limit, mixins=None, dry_run=False):
    """The native mods that apply and compile here, written over `tree`; their content into OUT/native-content."""
    bundles, data = [], {}
    for entry, version in found:
        if entry.get("kind") != "native-mod":
            continue
        try:
            raw = download(nc, entry, version)
            bundle = nc.Bundle(raw, "registry")
        except Exception as e:  # noqa: BLE001
            report["left_out"].append({"id": entry["id"], "kind": "native-mod", "why": f"download: {e}"})
            continue
        bundles.append(bundle)
        data[bundle.id] = raw
    if limit:
        bundles = bundles[:limit]
    # API packages are staged as crates by the launcher only (native_mods/api.rs), and the mods needing them go too.
    gone = {b.id for b in bundles if b.api or not b.mixins_content}
    while more := {b.id for b in bundles if b.id not in gone and any(n in gone for n in b.needs)}:
        gone |= more
    for b in bundles:
        if b.id in gone:
            report["left_out"].append({"id": b.id, "kind": "native-mod",
                                       "why": "API package (the launcher builds it)" if b.api else
                                       "nothing to apply" if not b.mixins_content else "needs a mod left out"})
    left = [b for b in bundles if b.id not in gone]
    if not left:
        return False
    revision = subprocess.run(["git", "-C", str(tree), "rev-parse", "HEAD"], check=True, capture_output=True,
                              text=True).stdout.strip()
    source = pristine(tree, nc.WORK / "source")
    tool = Path(mixins) if mixins else nc.mixins_tool(left)
    stage = None
    for round_ in range(COMPILE_ROUNDS):
        stage, refused = nc.apply(tool, source, left, revision, "ios")
        for i, d in refused.items():
            report["left_out"].append({"id": i, "kind": "native-mod", "why": f"{d.get('code')}: {d.get('message')}"})
        left = [b for b in left if b.id not in refused]
        if stage is None or not left:
            return False
        log(f"Round {round_ + 1}: checking {len(left)} native mods together")
        errors = check(nc, stage, target, True)
        if errors is None:
            break
        traced = nc.traced(errors, source, left)
        if not traced:
            log("The errors are in no mod's code: no native mod goes in.")
            for b in left:
                report["left_out"].append({"id": b.id, "kind": "native-mod", "why": "the game didn't compile with them"})
            return False
        gone = set(traced)
        while more := {b.id for b in left if b.id not in gone and any(n in gone for n in b.needs)}:
            gone |= more
        for i in sorted(gone):
            e = traced.get(i, {"code": "E_DEPENDENCY", "message": "needs a mod left out"})
            report["left_out"].append({"id": i, "kind": "native-mod", "why": f"{e['code']}: {e['message']}"})
        left = [b for b in left if b.id not in gone]
        stage = None
    else:
        return False
    if stage is None:
        return False
    # The game, with the mods, over this workspace (its own .git, target and untracked files stay).
    if not dry_run:
        subprocess.run(["rsync", "-a", "--checksum", "--exclude", ".git", "--exclude", "target",
                        f"{stage}/", f"{tree}/"], check=True)
    for b in left:
        archive = zipfile.ZipFile(io.BytesIO(data[b.id]))
        names = [n for n in archive.namelist() if not n.endswith("/")]
        if "horizon-mod.toml" in names:
            # A combined mod's content, beside the game as the launcher installs it (native_mods/source.rs).
            for n in names:
                if n == "horizon-native.json" or n.startswith("mixins/") or ".." in Path(n).parts:
                    continue
                path = out / "native-content" / b.id / n
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(archive.read(n))
        report["native"].append({"id": b.id, "version": b.version})
        log(f"  native: {b.id} {b.version}")
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--registry", type=Path, required=True, help="a clone of horizon-rust/horizon-mods")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--check-target", default="aarch64-apple-ios",
                        help="the target `cargo check` builds for; empty: the host's horizon-client")
    parser.add_argument("--no-native", action="store_true")
    parser.add_argument("--limit", type=int, default=0, help="at most this many native mods (a quick try)")
    parser.add_argument("--mixins", help="a horizon-mixins binary to use (else the registry's choice, built)")
    parser.add_argument("--dry-run", action="store_true", help="don't write the mods over this workspace")
    args = parser.parse_args()
    sys.path.insert(0, str(args.registry / "scripts"))
    import native_compat as nc  # noqa: E402 (the registry's own: horizon-mixins, apply, tracing)
    nc.native_trace = __import__("native_trace")
    shutil.rmtree(args.out, ignore_errors=True)
    args.out.mkdir(parents=True)
    report = {"game": GAME, "native": [], "content": [], "left_out": []}
    found = entries(args.registry)
    content(nc, found, args.out, report)
    report["mods_feature"] = False
    if not args.no_native:
        try:
            built = native(nc, found, ROOT, args.out, report, args.check_target, args.limit, args.mixins,
                           args.dry_run)
            report["mods_feature"] = built and has_mods_feature(ROOT)
        except SystemExit as e:
            log(f"Native mods: {e}")
            report["left_out"].append({"id": "*", "kind": "native-mod", "why": str(e)})
    (args.out / "Registry").mkdir(exist_ok=True)
    (args.out / "Registry" / "registry.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    log(f"{len(report['native'])} native mods built in, {len(report['content'])} content files,"
        f" {len(report['left_out'])} left out.")
    # The build reads whether to turn on Horizon's `mods` feature (only when it has one).
    print("1" if report["mods_feature"] else "0")


if __name__ == "__main__":
    main()
