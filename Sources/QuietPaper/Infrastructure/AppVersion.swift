/// Quiet Paper 当前版本号（唯一来源）。
///
/// 版本号由打包脚本 `scripts/build-app.sh` 维护：日常打包会自动递增补丁号并写回本文件；
/// 标签发布会校验并复用这里已有的版本，同时同步到 app 包 Info.plist。
/// 设置面板的「最新版本」区块直接展示该常量，请勿手动修改。
enum AppVersion {
    /// 形如 major.minor.patch，例如 "1.0.1"。
    static let current = "1.0.26"
}
