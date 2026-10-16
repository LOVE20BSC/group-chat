# LOVE20BSC Group Chat

Group Chat 负责公开链上群聊业务（`GroupChat`、`GroupAdmin`、`GroupMember`、`GroupChatBanList`、规则 source、typed Manager）与 **Group Chat Delegate**，依赖 `core` 和 `action`。

迁移方式：每个合约先以固定旧提交建立原始快照，再按小步提交改造成 BSC 版本。旧代码来源：`LOVE20TKM/group-chat`（提交 `ce21ea8`）、`LOVE20TKM/group`（提交 `2eb6d6c`，仅 `GroupDelegate`），见 [repositories.md](https://github.com/LOVE20BSC/matt-gov/blob/main/docs/repositories.md#旧代码基线)。

## 依赖

| 子模块 | 用途 |
| --- | --- |
| `lib/core` | `MemberNFT`、`Phase` 等 Core 接口的唯一来源与测试夹具用的 Core 实现 |
| `lib/action` | `IGroupActionIndexes.isGroupMember` 等 Action 层接口的来源 |
| `lib/libs` | 共享库（分页、集合原语、按轮历史） |
| `lib/openzeppelin-contracts` | 标准 ERC 与数学库 |
| `lib/forge-std` | 测试与脚本 |

自有接口以 `matt-gov` 的 `interfaces/group-chat/` 为唯一来源，实现前冻结为 ABI 对账基准；仓库实现完成后接口迁入本仓 `src/interfaces/`。Core 与 Action 的接口不走暂存副本，直接使用 `lib/core/src/interfaces/` 与 `lib/action/src/interfaces/`。

依赖版本固定在同一提交的 `.gitmodules` + `foundry.lock`，不在文档中另行登记。

## 当前状态

- 仓库骨架与工具链已建立，编译基线为 Solidity `0.8.37`、Foundry `1.8.1`、`evm_version = "osaka"`，不使用 `via_ir`。
- 迁移范围见 [group-chat 规格](https://github.com/LOVE20BSC/matt-gov/blob/main/docs/specs/group-chat/README.md)，差异见 [CHANGES-group-chat.md](https://github.com/LOVE20BSC/matt-gov/blob/main/docs/specs/CHANGES-group-chat.md)。

## 构建与测试

```sh
git submodule update --init --recursive
forge build --force --deny warnings
forge test
```
