# packrelay 资源分发仓库

本仓库由 [packrelay](https://github.com/chm413/packrelay) 插件自动维护，只用于分发 Minecraft 基岩版（BDS）资源包，**请不要手工提交**。

## 结构

| 路径 | 说明 |
| --- | --- |
| `packs/<slug>/` | 资源包源码与元数据（`manifest.json`、`pack_icon.png` 等），由插件推送 |
| `packs/index.json` | 资源包清单：uuid / version / 内容哈希 / tag / 资产名，由插件渲染 |
| `.github/workflows/release-packs.yml` | 自动打包发布流水线，由插件写入 |
| `scripts/release.sh` | 打 zip、创建 Release、回写 `release.json`，由插件写入 |
| Releases | 每个资源包版本一个 zip 资产，作为 CDN 下载地址 |

## 工作方式

1. 服务端扫描资源包目录 → 计算内容哈希 → 有变化才提交并推送 `packs/`
2. GitHub Actions 按 `index.json` 里的 tag/资产名打包并创建 Release
3. 插件轮询 Release 就绪后，把 Release 资产地址（可经镜像）写入 BDS 的 CDN 配置

源码、插件与完整文档见 <https://github.com/chm413/packrelay>。
