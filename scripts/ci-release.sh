#!/usr/bin/env bash
# mcpack-sync: 资源包发布脚本（与 .github/workflows/release.yml 同源）
#
# 职责：
#   1) 识别本次 push 改了哪些 packs/<slug>
#   2) 从 index.json 读取插件预先渲染好的 tag / assetName（保证与插件取回的名字一致）
#   3) 打包为 zip
#   4) 创建 GitHub Release（--gh），或落地到本地目录（--fs，供离线端到端验证）
#
# 用法：
#   bash scripts/ci-release.sh --gh
#   bash scripts/ci-release.sh --fs [输出目录]
set -euo pipefail

MODE="${1:---gh}"
OUT_DIR="${2:-./.releases}"

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

json_field() { # json_field <json> <field>
  node -e 'const o=JSON.parse(process.argv[1]);process.stdout.write(String(o[process.argv[2]]??""))' "$1" "$2"
}

lookup_pack() { # lookup_pack <slug> -> index.json 中的条目 JSON
  node -e '
    const fs=require("fs");
    const slug=process.argv[1];
    if(!fs.existsSync("index.json")) process.exit(0);
    const idx=JSON.parse(fs.readFileSync("index.json","utf8"));
    const p=(idx.packs||[]).find(x=>x.slug===slug);
    if(p) process.stdout.write(JSON.stringify(p));
  ' "$1"
}

# rev-parse 不带 --verify 时会把非法修订原样回显到 stdout，必须加 --verify
prev="$(git rev-parse --verify -q "HEAD~1" 2>/dev/null || true)"
if [ -z "$prev" ]; then
  # 首次提交没有 HEAD~1：直接列 packs/ 下的一级目录
  changed="$(git ls-tree -d --name-only "HEAD:packs" 2>/dev/null || true)"
else
  changed="$(git diff --name-only "$prev" HEAD -- packs | awk -F/ 'NF>1{print $2}' | sort -u)"
fi

if [ -z "${changed:-}" ]; then
  echo "::notice::no pack changes in this push"
  exit 0
fi

echo "changed packs: $(echo "$changed" | tr '\n' ' ')"
mkdir -p "$OUT_DIR"

for slug in $changed; do
  meta="$(lookup_pack "$slug")"
  if [ -z "$meta" ]; then
    echo "::warning::slug '$slug' not found in index.json, skipped"
    continue
  fi

  tag="$(json_field "$meta" tag)"
  asset="$(json_field "$meta" assetName)"
  if [ -z "$tag" ] || [ -z "$asset" ]; then
    echo "::warning::missing tag/assetName for '$slug', skipped"
    continue
  fi

  zip_path="$OUT_DIR/$tag/$asset"
  mkdir -p "$OUT_DIR/$tag"
  rm -f "$zip_path"

  # 下面要 cd 进包目录打包，相对路径 $zip_path 会解析到包目录下面去（实测踩坑：
  # "./.releases/<tag>/<asset>.zip" 在 cd 后变成 packs/<slug>/.releases/...，zip 直接
  # "Could not create output file"）。先把输出路径转成绝对路径再进子 shell。
  zip_abs="$(cd "$(dirname "$zip_path")" && pwd)/$(basename "$zip_path")"

  # 优先系统 zip；否则用 mcpack-sync 自带的 store 打包器；最后退回 tar
  if command -v zip >/dev/null 2>&1; then
    ( cd "packs/$slug" && zip -qr "$zip_abs" . )
  elif command -v mcpsync >/dev/null 2>&1; then
    mcpsync package --input "packs/$slug" --output "$zip_abs" >/dev/null
  else
    ( cd "packs/$slug" && tar --force-local -a -c -f "$zip_abs" . )
  fi

  size="$(wc -c < "$zip_abs" | tr -d ' ')"
  sha="$(sha256sum "$zip_abs" | cut -d' ' -f1)"
  echo "packaged $slug -> $zip_path (${size} bytes, sha256=$sha)"

  if [ "$MODE" = "--gh" ]; then
    if gh release view "$tag" >/dev/null 2>&1; then
      echo "::notice::release $tag already exists, uploading asset if missing"
      gh release upload "$tag" "$zip_abs" --clobber
    else
      gh release create "$tag" "$zip_abs" \
        --title "$tag" \
        --notes "Automated release for \`$slug\` by mcpack-sync." \
        --latest
    fi
  else
    base="${MCPACK_RELEASE_BASE_URL:-http://127.0.0.1:8731/downloads}"
    node -e '
      const fs=require("fs");
      const [tag,asset,size,url,out,slug]=process.argv.slice(1);
      const published=new Date().toISOString().replace(/\.[0-9]+Z$/,"Z");
      const rel={
        tag_name:tag, name:tag, html_url:url, published_at:published,
        draft:false, prerelease:false,
        body:"Automated release for "+slug+" by mcpack-sync.",
        assets:[{name:asset, browser_download_url:url, size:Number(size), updated_at:published}]
      };
      fs.writeFileSync(out, JSON.stringify(rel,null,2));
    ' "$tag" "$asset" "$size" "$base/$tag/$asset" "$OUT_DIR/$tag/release.json" "$slug"
    echo "wrote $OUT_DIR/$tag/release.json"
  fi
done
