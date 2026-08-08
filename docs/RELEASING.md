# 发布 Quiet Paper

GitHub Release 是公开下载和历史版本的唯一入口。版本使用 `vX.Y.Z` 标签；工作流会在 Apple Silicon 与 Intel runner 上分别构建，上传两份 ZIP 和对应的 SHA-256。

## 准备版本

`AppVersion.current` 必须与标签版本一致。本地打包默认会自动增加补丁版本，因此发布前只运行一次：

```bash
./scripts/build-app.sh
./scripts/run-tests.sh
```

确认设置页和生成的应用包显示正确版本后，提交由打包脚本产生的版本改动，再创建同名标签：

```bash
VERSION=$(sed -n 's/^    static let current = "\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)"$/\1/p' Sources/QuietPaper/Infrastructure/AppVersion.swift)
git add Sources/QuietPaper/Infrastructure/AppVersion.swift
git commit -m "Release $VERSION"
git tag -a "v$VERSION" -m "Quiet Paper $VERSION"
git push origin main "v$VERSION"
```

推送标签后，`.github/workflows/release.yml` 会完成余下工作。两个架构必须全部构建成功，Release 才会发布。失败的历史任务可以在 Actions 页面重新运行；也可以手动运行该工作流并填写已经存在的标签。

## 本地检查发布包

发布打包不会再次修改版本号：

```bash
./scripts/package-release.sh "$VERSION" apple-silicon
./scripts/package-release.sh "$VERSION" intel
```

第二条命令需要本机具备 Intel 交叉编译环境。生成的文件位于 `release/`，该目录不会提交到 Git。

## Developer ID 签名与公证

没有 Apple Developer 证书时，工作流仍会生成 ad-hoc 签名的可运行应用，但首次打开需要在 Finder 中右键选择“打开”。要让下载后的应用直接双击运行，需要有效的 Apple Developer Program 账号和 `Developer ID Application` 证书。

在仓库 Settings → Secrets and variables → Actions 中配置：

- `MACOS_CERTIFICATE_P12`：P12 文件的 Base64 内容。
- `MACOS_CERTIFICATE_PASSWORD`：导出 P12 时设置的密码。
- `APPLE_ID`：用于公证的 Apple ID。
- `APPLE_APP_PASSWORD`：该 Apple ID 的 app-specific password。
- `APPLE_TEAM_ID`：Apple Developer Team ID。

五项配置完整后，工作流会自动导入临时钥匙串、使用 hardened runtime 签名、提交 Apple 公证、staple 公证票据，再生成最终 ZIP。临时证书与钥匙串会在每个构建任务结束时删除。

## 版本与资产核对

发布完成后应检查：

- Release 标题与标签版本一致。
- 同时存在 `Apple-Silicon.zip`、`Intel.zip` 和各自的 `.sha256`。
- 解压后 `codesign --verify --deep --strict QuietPaper.app` 通过。
- `lipo -archs QuietPaper.app/Contents/MacOS/QuietPaper` 与下载的架构一致。
- Release 页面可以继续访问旧版本，最新版链接指向刚发布的版本。
