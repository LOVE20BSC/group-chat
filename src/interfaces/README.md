# Interfaces

- 根目录：主协议与共享群级配置稳定 ABI。
- `external/`：上游合约或通用标准的最小适配接口，只保留本仓库实际调用的函数和类型。
- `managers/`：typed Manager 的外部稳定 ABI；按 base / token / action 公共面拆分。
- `plugins/`：发帖前后插件接口。
- `sources/`：内置 ScopeSource / BanSource 的外部稳定 ABI。
