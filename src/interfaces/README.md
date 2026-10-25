# Interfaces

- 根目录：主协议与共享群级配置稳定 ABI；每个模块的错误集中在其 `I<Name>Errors` 接口。
- `managers/`：typed Manager 的外部稳定 ABI。`IManagerBase` 承载共享错误、槽位 getter、`TYPE_CODE()` 与 `IPostScopeSource` / `IBanVoteWeightSource` / `IERC721Receiver` 的公共面；`ITokenScopeManagerBase` / `ITokenActionScopeManagerBase` 分别扩展代币侧与行动侧，`ActionNotExist` 属于行动侧 `ITokenActionScopeManagerBaseErrors`。
- `plugins/`：发帖前后插件接口。
- `sources/`：内置 ScopeSource / BanSource 的外部稳定 ABI。
