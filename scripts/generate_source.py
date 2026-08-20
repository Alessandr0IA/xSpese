#!/usr/bin/env python3

"""Aggiorna una source SideStore usando i metadati reali dell'IPA."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import plistlib
from pathlib import Path
import re
import sys
from urllib.parse import quote
import zipfile


def fail(message: str) -> None:
    raise SystemExit(f"Errore: {message}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="CFBundleShortVersionString")
    parser.add_argument("--build", required=True, help="CFBundleVersion")
    parser.add_argument("--bundle-id", required=True, help="CFBundleIdentifier")
    parser.add_argument("--ipa", required=True, type=Path, help="Percorso dell'IPA")
    parser.add_argument("--repo", required=True, help="Repository GitHub OWNER/REPO")
    parser.add_argument("--tag", required=True, help="Tag GitHub, ad esempio v0.1.0")
    parser.add_argument("--branch", default="main", help="Branch che ospita source.json")
    parser.add_argument("--source", default=Path("source.json"), type=Path)
    parser.add_argument("--output", type=Path, help="Output; predefinito: sovrascrive --source")
    parser.add_argument("--notes-file", type=Path, help="CHANGELOG da cui estrarre le note")
    parser.add_argument("--date", help="Data ISO 8601; predefinita: data UTC corrente")
    return parser.parse_args()


def ipa_metadata(ipa_path: Path) -> dict[str, str]:
    if not ipa_path.is_file():
        fail(f"IPA non trovato: {ipa_path}")
    if not zipfile.is_zipfile(ipa_path):
        fail(f"il file non è uno ZIP/IPA valido: {ipa_path}")

    with zipfile.ZipFile(ipa_path) as archive:
        candidates = [
            name
            for name in archive.namelist()
            if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)
        ]
        if len(candidates) != 1:
            fail("l'IPA deve contenere un solo Payload/<App>.app/Info.plist")
        plist = plistlib.loads(archive.read(candidates[0]))

    required = {
        "version": "CFBundleShortVersionString",
        "build": "CFBundleVersion",
        "bundle_id": "CFBundleIdentifier",
    }
    values: dict[str, str] = {}
    for output_key, plist_key in required.items():
        value = plist.get(plist_key)
        if value is None:
            fail(f"{plist_key} assente dall'Info.plist dell'IPA")
        values[output_key] = str(value)
    return values


def changelog_notes(path: Path | None, version: str) -> str:
    if path is None or not path.is_file():
        return f"Release {version}."

    lines = path.read_text(encoding="utf-8").splitlines()
    header = re.compile(rf"^##\s+(?:\[)?{re.escape(version)}(?:\])?(?:\s+-.*)?\s*$")
    collecting = False
    collected: list[str] = []
    for line in lines:
        if header.match(line):
            collecting = True
            continue
        if collecting and line.startswith("## "):
            break
        if collecting:
            collected.append(line)
    notes = "\n".join(collected).strip()
    return notes or f"Release {version}."


def main() -> None:
    args = parse_args()
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:[+-][0-9A-Za-z.-]+)?", args.version):
        fail(f"versione non SemVer: {args.version}")
    if args.tag != f"v{args.version}":
        fail(f"il tag {args.tag} non coincide con la versione v{args.version}")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo):
        fail("--repo deve avere il formato OWNER/REPO")
    if not args.branch.strip():
        fail("--branch non può essere vuoto")

    metadata = ipa_metadata(args.ipa)
    expected = {
        "version": args.version,
        "build": args.build,
        "bundle_id": args.bundle_id,
    }
    for key, value in expected.items():
        if metadata[key] != value:
            fail(f"mismatch {key}: argomento={value}, IPA={metadata[key]}")

    if not args.source.is_file():
        fail(f"source JSON non trovata: {args.source}")
    try:
        source = json.loads(args.source.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as error:
        fail(f"source JSON non leggibile: {error}")

    apps = source.get("apps")
    if not isinstance(apps, list):
        fail("source.json deve contenere un array apps")
    app = next((item for item in apps if item.get("bundleIdentifier") == args.bundle_id), None)
    if app is None:
        fail(f"app {args.bundle_id} non trovata in source.json")

    repo_url = f"https://github.com/{args.repo}"
    raw_root = f"https://raw.githubusercontent.com/{args.repo}/{quote(args.branch, safe='')}"
    icon_url = f"{raw_root}/assets/icon.png"
    ipa_url = f"{repo_url}/releases/download/{quote(args.tag, safe='')}/{quote(args.ipa.name, safe='')}"
    release_date = args.date or dt.datetime.now(dt.timezone.utc).date().isoformat()
    ipa_bytes = args.ipa.read_bytes()
    release_notes = changelog_notes(args.notes_file, args.version)

    source.update(
        {
            "sourceURL": f"{raw_root}/source.json",
            "website": repo_url,
            "iconURL": icon_url,
        }
    )
    app.update(
        {
            "version": args.version,
            "versionDate": release_date,
            "versionDescription": release_notes,
            "downloadURL": ipa_url,
            "size": len(ipa_bytes),
            "iconURL": icon_url,
        }
    )

    version_entry = {
        "version": args.version,
        "buildVersion": args.build,
        "date": release_date,
        "downloadURL": ipa_url,
        "size": len(ipa_bytes),
        "sha256": hashlib.sha256(ipa_bytes).hexdigest(),
        "minOSVersion": "17.0",
        "localizedDescription": release_notes,
    }

    versions = app.setdefault("versions", [])
    if not isinstance(versions, list):
        fail("apps[].versions deve essere un array")
    versions[:] = [
        item
        for item in versions
        if not (
            str(item.get("version")) == args.version
            and str(item.get("buildVersion")) == args.build
        )
    ]
    versions.insert(0, version_entry)

    output = args.output or args.source
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(source, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Source aggiornata: {output}")
    print(f"Download: {ipa_url}")


if __name__ == "__main__":
    main()
