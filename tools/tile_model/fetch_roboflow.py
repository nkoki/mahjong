"""Roboflow Universe のデータセット（CC BY 4.0）を COCO 形式で取得する。

API キーは環境変数 ROBOFLOW_API_KEY から読む（ファイルやログには書かない）。
ライセンスが CC BY 4.0 であることを API の情報で確かめ、出典の情報を attribution.json に書く。

使い方:
  python fetch_roboflow.py --out data/roboflow            # datasets.json の全部
  python fetch_roboflow.py --out data/roboflow --only hust
"""

import argparse
import io
import json
import os
import sys
import time
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

API = "https://api.roboflow.com"
ALLOWED_LICENSES = {"cc by 4.0", "cc-by-4.0", "cc by-4.0", "cc-by 4.0", "creative commons attribution 4.0"}


def get_json(path: str, key: str):
    url = f"{API}/{path}?{urllib.parse.urlencode({'api_key': key})}"
    req = urllib.request.Request(url, headers={"User-Agent": "mahjong-tile-model-fetch"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)


def find_license(obj):
    """API の応答の中から license の値を探す"""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k.lower() == "license" and isinstance(v, str):
                return v
        for v in obj.values():
            r = find_license(v)
            if r:
                return r
    elif isinstance(obj, list):
        for v in obj:
            r = find_license(v)
            if r:
                return r
    return None


def resolve_project(ds, key):
    if ds.get("project"):
        return ds["project"]
    ws = get_json(ds["workspace"], key)
    projects = ws.get("workspace", {}).get("projects", [])
    for p in projects:
        if p.get("name", "").strip().lower() == ds["name"].strip().lower():
            return p["id"].split("/")[-1]
    names = [p.get("name") for p in projects]
    raise SystemExit(f"{ds['workspace']} に {ds['name']!r} が見つかりません（あるもの: {names}）")


def fetch(ds, out: Path, key: str):
    project = resolve_project(ds, key)
    info = get_json(f"{ds['workspace']}/{project}", key)
    proj = info.get("project", info)
    license_ = find_license(proj) or find_license(info)
    if not license_ or license_.strip().lower() not in ALLOWED_LICENSES:
        raise SystemExit(f"{ds['display_name']}: ライセンスが CC BY 4.0 ではありません（{license_!r}）。取得をやめます")
    versions = info.get("versions", [])
    if ds.get("version"):
        version = int(ds["version"])
    elif versions:
        version = max(int(str(v["id"]).split("/")[-1]) for v in versions)
    else:
        raise SystemExit(f"{ds['display_name']}: バージョンがありません")

    # 書き出し（まだ作られていなければ Roboflow 側で作られるのを待つ）
    for _ in range(60):
        exp = get_json(f"{ds['workspace']}/{project}/{version}/coco", key)
        link = exp.get("export", {}).get("link")
        if link:
            break
        time.sleep(10)
    else:
        raise SystemExit(f"{ds['display_name']}: 書き出しが終わりませんでした")

    dest = out / ds["key"]
    dest.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(link, timeout=600) as r:
        data = r.read()
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for m in z.infolist():
            p = Path(m.filename)
            if p.is_absolute() or ".." in p.parts:
                raise SystemExit(f"zip の中に不正なパスがあります: {m.filename}")
        z.extractall(dest)

    attribution = {
        "key": ds["key"],
        "title": ds["display_name"],
        "project_name": proj.get("name", ds["name"]),
        "author": ds["workspace"],
        "url": f"https://universe.roboflow.com/{ds['workspace']}/{project}",
        "version": version,
        "license": "CC BY 4.0",
        "license_url": "https://creativecommons.org/licenses/by/4.0/",
        "images": proj.get("images"),
        "classes": proj.get("classes"),
        "fetched": time.strftime("%Y-%m-%d"),
    }
    (dest / "attribution.json").write_text(json.dumps(attribution, ensure_ascii=False, indent=2))
    print(json.dumps(attribution, ensure_ascii=False, indent=2))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--config", type=Path, default=Path(__file__).with_name("datasets.json"))
    ap.add_argument("--only", nargs="*")
    args = ap.parse_args()
    key = os.environ.get("ROBOFLOW_API_KEY", "").strip()
    if not key:
        sys.exit("環境変数 ROBOFLOW_API_KEY が設定されていません")
    cfg = json.loads(args.config.read_text())
    for ds in cfg["datasets"]:
        if args.only and ds["key"] not in args.only:
            continue
        fetch(ds, args.out, key)


if __name__ == "__main__":
    main()
