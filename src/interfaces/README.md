# Interfaces

- 根目录：主协议与共享群级配置稳定 ABI。
- `managers/`：typed Manager 的外部稳定 ABI。`IBaseManager` 承载共享错误、槽位 getter 与 `IPostScopeSource` / `IBanVoteWeightSource` / `IERC721Receiver` 的公共面；`IBaseTokenScopeManager` / `IBaseTokenActionScopeManager` 分别扩展代币侧与行动侧，`ActionIdNotExist` 内联在行动侧。
- `plugins/`：发帖前后插件接口。
- `sources/`：内置 ScopeSource / BanSource 的外部稳定 ABI。
