# group-chat 部署脚本

统一结构见根目录 `LOVE20BSC/matt-gov/docs/dev-standards.md` 第六节；本文只记录本库特有部分。

```
script/
├── deploy/
│   ├── one_click_deploy.sh      # 入口：纯编排（解析 keystore 密码、按序调用三个步骤、校验失败回滚地址文件）
│   ├── 11_deploy.sh             # 步骤一：部署 13 个合约并写入 addresses.group-chat.params
│   ├── 21_check.sh               # 步骤二：只读校验部署与参数绑定，可重复运行
│   ├── 31_verify.sh              # 步骤三：开源验证，链未配 verifier 时跳过
│   └── DeployGroupChat.s.sol     # Foundry 部署脚本（输出 KEY=VALUE 地址行，由 11_deploy.sh 落盘）
└── network/<链名><链id>_<部署类型>/
    ├── .account                  # KEYSTORE_ACCOUNT / ACCOUNT_ADDRESS / KEYSTORE_PASSWORD（可选），已 gitignore
    ├── network.params            # CHAIN_ID / RPC_URL（接入浏览器的链另带 VERIFIER / VERIFIER_URL）
    ├── group-chat.params         # 本库 13 个合约的构造参数
    ├── addresses.group-chat.params  # 本库已部署地址，11_deploy.sh 写入
    ├── addresses.core.params     # 被依赖方：MemberNFT、Phase（从 core 对应网络复制）
    └── addresses.action.params   # 被依赖方：ActionTarget、GroupActionExecutor（从 action 对应网络复制）
```

## 用法

```sh
# 一键部署（本地 anvil 或已配置的公网）
script/deploy/one_click_deploy.sh <network>

# 分步执行（每步自包含，互不调用）
script/deploy/11_deploy.sh <network>
script/deploy/21_check.sh <network>
script/deploy/31_verify.sh <network>
```

`one_click_deploy.sh` 只做编排：先重置并解析 `KEYSTORE_PASSWORD`（环境 → `.account` → macOS 弹窗，全程一次），
备份地址文件后依次执行部署与校验；校验失败则回滚到上次已保存的地址，不属于失败重试的一部分。
广播阶段或其后的校验失败时，`11_deploy.sh` 保留部署日志并打印日志与 broadcast 产物路径；广播前失败只清理本次临时文件。
keystore 密码不继承调用方环境变量，非交互场景请写进 `.account`。密码经权限 600 的临时文件以
`--password-file` 传给 forge，不进进程参数；广播结束或脚本退出时删除。

## 部署内容

`DeployGroupChat.s.sol` 依次部署本库全部 13 个合约：`GroupChatDelegate` → `GroupAdmin` → `GroupChat` →
`GroupChatBanList` / `AdminBanSource` / `GovVotedBanSource` / `GroupMember` / `GroupMemberScope` /
`GroupJoinScopeSource` → 四个 Manager（`TokenMainManager`、`TokenGovManager`、`TokenActionGovManager`、
`TokenActionMainManager`）。

依赖项（MemberNFT、Phase、ActionTarget、GroupActionExecutor）必须在广播前已部署，由
`DeployGroupChat.s.sol` 在 `startBroadcast()` 前校验代码与派生绑定，避免白广播本库合约；`11_deploy.sh`
只做文件、链、账户与密码编排。

MemberNFT 的 `MAX_NAME_LENGTH` 必须 ≥ 各 Manager 的 `bytes(TYPE_CODE()).length + 9`（1 字节分隔符 + 4 位 hex + 4 字节 Test 前缀；当前四类 2 字节类型码即 11；默认 32 满足）。类型码由各 Manager 自己定义，不设集中清单；广播前 Manager 尚未部署，脚本按「当前最长类型码 2 字节」预检 `MAX_NAME_LENGTH ≥ 11`（该假设由 `testT181` 对四个已部署 Manager 的实际 `TYPE_CODE()` 反向锁定），`21_check.sh` 部署后按各 Manager 的 `TYPE_CODE()` 独立复核；合约不再检查。建议保持在 32–64，payload 丢弃时的随机串长度会随 MAX 线性增长。

`GROUP_CHAT_ACTION_RECENT_ROUNDS` 必须 >0，由 `DeployGroupChat.s.sol` 的 `_validateConfig` 广播前校验，`21_check.sh` 复核两个 action Manager 的 `RECENT_ROUNDS`。

构造期静态校验已按 dev-standards §5.7 从合约移除，统一放在部署脚本：

- `DeployGroupChat.s.sol` 广播前：被依赖方与派生依赖（submit/vote/stake/launch）有代码且与 core 地址文件一致，`ActionTarget.memberNFTAddress/phaseAddress` 与 core 一致，MemberNFT 根代币与 `LOVE20_TOKEN_ADDRESS` 一致，`Phase.ORIGIN_PHASE_BLOCKS() > 0`、MemberNFT `MAX_NAME_LENGTH` 名称空间下限、group-chat 参数（`BAN_THRESHOLD_RATIO` 允许 0，仅要求 ≤1e18；其余非零）、插件地址非零时有代码；部署后 `_validateDeployment` 校验完整绑定图（Group/Delegate/Admin/Chat/Member/Scope/Source/Manager 的地址、上限与 recentRounds）。
- `11_deploy.sh` 只负责自包含加载、链/账户/密码、调用 forge 与地址文件原子写入，不重复上述校验。
- `21_check.sh` 部署后独立复核绑定、参数与各 Manager 的 `TYPE_CODE()` 名称空间；运行期输入/状态校验（token/action/member/auth/content）仍由合约执行。

## 新增网络

```sh
mkdir -p script/network/<链名><链id>_<部署类型>
cp script/network/anvil31337_dev/{network.params,group-chat.params} script/network/<新目录>/
```

`.account` 已 gitignore、不在拷贝范围，需按部署账户自建（`KEYSTORE_ACCOUNT` / `ACCOUNT_ADDRESS` /
`KEYSTORE_PASSWORD`，密码可留空走交互）；`addresses.group-chat.params` 无需自建，由 `11_deploy.sh` 写入。

被依赖方地址从对应网络的 `core` / `action` 地址文件复制后填入本目录的
`addresses.core.params` / `addresses.action.params`；留零时部署会在广播前明确报错。
