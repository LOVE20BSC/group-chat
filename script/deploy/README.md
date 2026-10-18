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
    ├── network.params            # CHAIN_ID / RPC_URL（thinkium 另带 VERIFIER / VERIFIER_URL）
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
keystore 密码不继承调用方环境变量，非交互场景请写进 `.account`。

## 部署内容

`DeployGroupChat.s.sol` 依次部署本库全部 13 个合约：`GroupChatDelegate` → `GroupAdmin` → `GroupChat` →
`GroupChatBanList` / `AdminBanSource` / `GovVotedBanSource` / `GroupMember` / `GroupMemberScope` /
`GroupJoinScopeSource` → 四个 Manager（`TokenMainManager`、`TokenGovManager`、`TokenActionGovManager`、
`TokenActionMainManager`）。

依赖项（MemberNFT、Phase、ActionTarget、GroupActionExecutor）必须在广播前已部署，`11_deploy.sh` 用
`cast code` 校验，避免白广播本库合约。

## 新增网络

```sh
mkdir -p script/network/<链名><链id>_<部署类型>
cp script/network/anvil31337_dev/{network.params,group-chat.params} script/network/<新目录>/
```

被依赖方地址从对应网络的 `core` / `action` 地址文件复制后填入本目录的
`addresses.core.params` / `addresses.action.params`；留零时部署会在广播前明确报错。
