/// Quiet Paper 当前版本号（唯一来源）。
///
/// 版本号由打包脚本 `scripts/build-app.sh` 维护：每次打包都会自动递增补丁号并写回本文件，
/// 同时同步到 app 包 Info.plist 的 `CFBundleShortVersionString` / `CFBundleVersion`。
/// 设置面板的「最新版本」区块直接展示该常量，请勿手动修改。
enum AppVersion {
    /// 形如 major.minor.patch，例如 "1.0.1"。
    static let current = "1.0.26"
}
