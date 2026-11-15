#!/usr/bin/env python3
"""The AltStore / SideStore source for the iOS port, from this repo's `ios-v*` GitHub releases.

Each release with a `Horizon-<version>.ipa` asset is one version, newest first; its notes
(the Russian half, above `---`) are the version's description. The release step uploads the
result as `altstore.json`, so the source URL is always
https://github.com/<repo>/releases/latest/download/altstore.json
"""
import json
import subprocess
import sys

REPO = sys.argv[1] if len(sys.argv) > 1 else "neosay-dev/horizon-ios"
RAW = f"https://raw.githubusercontent.com/{REPO}/ios-port"


def gh(*args):
    return json.loads(subprocess.check_output(["gh", *args, "-R", REPO]))


versions = []
for r in gh("release", "list", "--limit", "100", "--json", "tagName"):
    tag = r["tagName"]
    if not tag.startswith("ios-v"):
        continue
    rel = gh("release", "view", tag, "--json", "tagName,publishedAt,createdAt,body,assets")
    version = tag.removeprefix("ios-v")
    ipa = next((a for a in rel["assets"] if a["name"] == f"Horizon-{version}.ipa"), None)
    if ipa is None:
        continue
    notes = (rel.get("body") or "").split("\n---", 1)[0].strip()
    versions.append({
        "version": version,
        "date": rel.get("publishedAt") or rel["createdAt"],
        "localizedDescription": notes,
        "downloadURL": ipa["url"],
        "size": ipa["size"],
        "minOSVersion": "17.0",
    })

versions.sort(key=lambda v: [int(p) if p.isdigit() else p for p in v["version"].split(".")], reverse=True)

source = {
    "name": "Horizon iOS",
    "identifier": "dev.neosay.horizon.source",
    "subtitle": "Minecraft Java Edition 26.3 на Rust",
    "description": "Неофициальный порт Horizon на iOS. Файлы игры берутся из своей копии Minecraft: Java Edition.",
    "iconURL": f"{RAW}/ios/Horizon/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
    "website": f"https://github.com/{REPO}",
    "tintColor": "#B9A4FF",
    "apps": [{
        "name": "Horizon",
        "bundleIdentifier": "dev.neosay.horizon",
        "developerName": "neosay-dev",
        "subtitle": "Minecraft Java Edition 26.3 на Rust",
        "localizedDescription": "Horizon — Minecraft: Java Edition 26.3, переписанный на Rust, на iPhone: "
            "лаунчер, сенсорное управление с редактором, виртуальная мышь, встроенные моды Horizon. "
            "Нужны файлы игры из своей копии Java Edition.",
        "iconURL": f"{RAW}/ios/Horizon/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png",
        "tintColor": "#B9A4FF",
        "category": "games",
        "screenshots": [f"{RAW}/docs/media/ios/gameplay.jpg", f"{RAW}/docs/media/ios/settings.jpg"],
        "versions": versions,
        "appPermissions": {
            "entitlements": ["com.apple.developer.kernel.increased-memory-limit",
                             "com.apple.developer.kernel.extended-virtual-addressing"],
            "privacy": {
                "NSLocalNetworkUsageDescription": "Horizon подключается к серверам и мирам в локальной сети (LAN).",
                "NSMicrophoneUsageDescription": "Голосовой чат в игре (мод Simple Voice Chat).",
            },
        },
    }],
    "news": [],
}
json.dump(source, sys.stdout, ensure_ascii=False, indent=2)
print()
