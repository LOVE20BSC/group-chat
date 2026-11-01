#!/usr/bin/env python3
"""Group-chat deployment regression checks with stubbed cast/forge/osascript.

临时工程根里放三个同名假命令，脚本调用被记入日志，再断言退出码、地址文件、
密码临时文件（内容/权限/清理）与广播失败时的日志保留行为。不碰真仓库、不碰真链。
"""
import hashlib
import json
import os
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path

SECRET_PASSWORD = "do-not-print-this-password"

ADDRESS_FIELDS = [
    "GROUP_ADMIN_ADDRESS",
    "GROUP_CHAT_ADDRESS",
    "GROUP_CHAT_BAN_LIST_ADDRESS",
    "ADMIN_BAN_SOURCE_ADDRESS",
    "GOV_VOTED_BAN_SOURCE_ADDRESS",
    "GROUP_MEMBER_ADDRESS",
    "GROUP_MEMBER_SCOPE_ADDRESS",
    "GROUP_JOIN_SCOPE_SOURCE_ADDRESS",
    "TOKEN_MAIN_MANAGER_ADDRESS",
    "TOKEN_GOV_MANAGER_ADDRESS",
    "TOKEN_ACTION_GOV_MANAGER_ADDRESS",
    "TOKEN_ACTION_MAIN_MANAGER_ADDRESS",
]

CORE_ADDRESSES = {
    "LOVE20_TOKEN_ADDRESS": "0x" + "55" * 20,
    "MEMBER_NFT_ADDRESS": "0x" + "11" * 20,
    "PHASE_ADDRESS": "0x" + "22" * 20,
    "SUBMIT_ADDRESS": "0x" + "66" * 20,
    "VOTE_ADDRESS": "0x" + "77" * 20,
    "STAKE_ADDRESS": "0x" + "88" * 20,
    "LAUNCH_ADDRESS": "0x" + "99" * 20,
}

ACTION_ADDRESSES = {
    "ACTION_TARGET_ADDRESS": "0x" + "33" * 20,
    "GROUP_ACTION_EXECUTOR_ADDRESS": "0x" + "44" * 20,
}

MANAGER_TYPE_CODES = {
    "TOKEN_MAIN_MANAGER_ADDRESS": "tm",
    "TOKEN_GOV_MANAGER_ADDRESS": "tg",
    "TOKEN_ACTION_GOV_MANAGER_ADDRESS": "ag",
    "TOKEN_ACTION_MAIN_MANAGER_ADDRESS": "am",
}


def fake_tool(tool, args):
    data = json.loads(Path(os.environ["MOCK_DATA"]).read_text())
    with Path(os.environ["MOCK_LOG"]).open("a") as log:
        log.write(json.dumps([tool, *args]) + "\n")
    if tool == "osascript":
        print("test-password")
    elif tool == "cast":
        if args[0] == "chain-id":
            print(os.environ.get("RPC_CHAIN", data["chain_id"]))
        elif args[0] == "code":
            print("0x01")
        elif args[0] == "call":
            signature = args[2]
            call_values = {
                "LOVE20_TOKEN_ADDRESS()(address)": data["core"]["LOVE20_TOKEN_ADDRESS"],
                "ORIGIN_PHASE_BLOCKS()(uint256)": "100",
                "SUBMIT_ADDRESS()(address)": data["core"]["SUBMIT_ADDRESS"],
                "VOTE_ADDRESS()(address)": data["core"]["VOTE_ADDRESS"],
                "STAKE_ADDRESS()(address)": data["core"]["STAKE_ADDRESS"],
                "LAUNCH_ADDRESS()(address)": data["core"]["LAUNCH_ADDRESS"],
                "MEMBER_NFT_ADDRESS()(address)": data["core"]["MEMBER_NFT_ADDRESS"],
                "PHASE_ADDRESS()(address)": data["core"]["PHASE_ADDRESS"],
                "MAX_NAME_LENGTH()(uint256)": "32",
                # 协议常量，21_check 只判非零；零值会让校验失败，触发一键部署的回滚分支。
                "MAX_CONTENT_LENGTH()(uint256)": "4096",
                "MAX_MENTIONED_SENDER_IDS()(uint256)": "32",
            }
            if signature == "TYPE_CODE()(string)":
                print('"' + data["type_codes"][args[1]] + '"')
            elif signature in call_values:
                print(call_values[signature])
            elif '"forge", "script"' in Path(os.environ["MOCK_LOG"]).read_text():
                # 21_check 的其余 getter：返回零值让校验失败，触发一键部署的回滚分支。
                print("0x" + "00" * 20 if signature.endswith("(address)") else "0")
            else:
                raise AssertionError(args)
        else:
            raise AssertionError(args)
    elif tool == "mktemp":
        if "-d" in args:
            print(tempfile.mkdtemp(dir=os.environ["MOCK_TMP"]))
        else:
            fd, path = tempfile.mkstemp(dir=os.environ["MOCK_TMP"])
            os.close(fd)
            print(path)
    elif tool == "forge":
        if args[0] != "script":
            raise AssertionError(args)
        if "--password" in args:
            print("CREDENTIAL_IN_ARGV", file=sys.stderr)
        password_file = args[args.index("--password-file") + 1] if "--password-file" in args else None
        if not password_file or not Path(password_file).is_file() or not Path(password_file).read_text():
            print("PASSWORD_FILE_MISSING", file=sys.stderr)
        else:
            mode = stat.S_IMODE(os.stat(password_file).st_mode)
            print(f"PASSWORD_MODE={mode:o}", file=sys.stderr)
            print("PASSWORD_SHA=" + hashlib.sha256(Path(password_file).read_bytes()).hexdigest(),
                  file=sys.stderr)
        if os.environ.get("DEPLOY_FAIL"):
            return 1
        broadcast = os.environ.get("MOCK_BROADCAST")
        if broadcast and Path(broadcast).exists():
            artifact = json.loads(Path(broadcast).read_text())
            artifact["timestamp"] = 0 if os.environ.get("STALE_BROADCAST") else int(time.time() * 1000)
            Path(broadcast).write_text(json.dumps(artifact, indent=2))
        for field, value in data["addresses"].items():
            if field != os.environ.get("OMIT_ADDRESS"):
                print(field + "= " + value)
    else:
        raise AssertionError(args)
    return 0


# params.sh 是 core / action / group-chat / dex 四份逐字节相同的副本：每个仓都要能独立部署，
# 文件无法共享，只能靠这个常量防止漂移。改动该文件时四个仓一起改，并同步这四个常量。
PARAMS_SH_SHA256 = "b3a8f64dc87d9e823a364de92e3bc79144d246f1c1a861cdcf95616042b8f840"


def params_shared_copy() -> None:
    """params.sh 必须与四仓共享副本逐字节相同。"""
    repo = Path(__file__).resolve().parents[1]
    digest = hashlib.sha256((repo / "script/deploy/params.sh").read_bytes()).hexdigest()
    assert digest == PARAMS_SH_SHA256, (
        "script/deploy/params.sh 与四仓共享副本不一致（sha256 " + digest + "）；"
        "把同一个文件同步到 core / action / group-chat / dex"
    )


def params_loader_cases() -> None:
    """params.sh：1e 写法展开、行尾注释、引号内 # 保留、逗号项去空格。"""
    repo = Path(__file__).resolve().parents[1]
    cases = [
        ("A=1e17\n", "100000000000000000"),
        ("A=3e15  # 0.30%\n", "3000000000000000"),
        ("A=1_000\n", "1000"),
        ('A="a # b"\n', "a # b"),
        ("A=1e17, 4e17\n", "100000000000000000,400000000000000000"),
        ("A=x1e5y\n", "x1e5y"),
    ]
    with tempfile.TemporaryDirectory(prefix="params-loader-test-") as directory:
        path = Path(directory) / "case.params"
        for text, expected in cases:
            path.write_text(text)
            result = subprocess.run(
                ["bash", "-c", '. "$1"; params_load "$2"; printf "%s" "$A"',
                 "bash", str(repo / "script/deploy/params.sh"), str(path)],
                text=True, capture_output=True)
            assert result.returncode == 0, (text, result.stderr)
            assert result.stdout == expected, (text, result.stdout)

    # params_unset_all 的键集来自文件本身：文件定义的键必须被清掉，文件没定义的键不受影响。
    with tempfile.TemporaryDirectory(prefix="params-unset-test-") as directory:
        path = Path(directory) / "case.params"
        path.write_text("A=1\n")
        result = subprocess.run(
            ["bash", "-c",
             '. "$1"; A=inherited; B=inherited; params_unset_all "$2"; printf "%s|%s" "${A:-<unset>}" "${B:-<unset>}"',
             "bash", str(repo / "script/deploy/params.sh"), str(path)],
            text=True, capture_output=True)
        assert result.returncode == 0, (result.stderr,)
        assert result.stdout == "<unset>|inherited", result.stdout


def params_unset_coverage() -> None:
    """每个 source params.sh 的部署脚本都必须在首次 params_load 之前清掉继承值，
    且 params_unset_all 的入参必须覆盖 params_load 读到的每个文件。"""
    repo = Path(__file__).resolve().parents[1]
    scripts = sorted((repo / "script/deploy").glob("*.sh"))
    assert scripts
    for script in scripts:
        text = script.read_text()
        if 'source "$SCRIPT_DIR/params.sh"' not in text:
            continue
        # 只看代码行：注释里出现同名字符串会让下面两条断言一起误通过。
        code = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
        assert "params_unset_all " in code, script
        assert code.index("params_unset_all ") < code.index("params_load "), script
        # 续行先拼回一行，否则只看得到首个参数。
        joined = code.replace("\\\n", " ")
        statement = re.search(r"params_unset_all(.*)", joined).group(1).split("\n")[0]
        unset_files = set(re.findall(r'"([^"]+)"', statement))
        load_files = set(re.findall(r'params_load\s+"([^"]+)"', joined))
        assert not load_files - unset_files, (script, load_files - unset_files)


def _params_required_pairs(text: str) -> set:
    """脚本里 params_require_keys/values 声明的 (params 文件名, 键)。"""
    code = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
    joined = code.replace("\\\n", " ")
    pairs = set()
    for match in re.finditer(r'params_require_(?:keys|values)\s+"[^"]*/([^"/]+)"([^\n]*)', joined):
        # 只看大写键名：尾部还有 `|| exit 1`。
        pairs.update((match.group(1), key) for key in re.findall(r"\b[A-Z][A-Z0-9_]*\b", match.group(2)))
    return pairs


def _params_loaded_files(text: str) -> set:
    """脚本里 params_load 读取的 params 文件名。"""
    code = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
    return set(re.findall(r'params_load\s+"[^"]*/([^"/]+)"', code))


def params_required_consistency() -> None:
    """必填键在调用点声明，没有中心键表：读取同一 params 文件的每个步骤必须声明同一组键。

    11/21/31 各自独立执行，谁都可以单独补一个 params_require_*；漏一处会让该步骤在缺键时
    拿空串继续、而另外两步仍然失败——半红半绿最难定位。
    """
    repo = Path(__file__).resolve().parents[1]
    deploy = repo / "script/deploy"
    assert not (deploy / "params-required.sh").exists(), (
        "必填键在调用点用 params_require_keys/values 声明，不再单设 params-required.sh")
    loaded = {}
    required = {}
    for script in sorted(deploy.glob("*.sh")):
        text = script.read_text()
        if 'source "$SCRIPT_DIR/params.sh"' not in text:
            continue
        for name in _params_loaded_files(text):
            loaded.setdefault(name, set()).add(script.name)
        for pair in _params_required_pairs(text):
            required.setdefault(pair, set()).add(script.name)
    for (file_name, key), scripts in sorted(required.items()):
        missing = loaded.get(file_name, set()) - scripts
        assert not missing, (file_name, key, sorted(missing))


def verifier_skip_never_production() -> None:
    """生产链不能出现在跳过列表：验证默认开启，跳过必须显式且只针对没有浏览器的链。"""
    profile = Path(__file__).resolve().parents[1] / "script/network/verifier.params"
    assert profile.is_file(), "script/network/verifier.params 缺失"
    text = profile.read_text()
    url = re.search(r"^ETHERSCAN_VERIFIER_URL=(.*)$", text, re.MULTILINE)
    skip = re.search(r"^VERIFY_SKIP_CHAIN_IDS=(.*)$", text, re.MULTILINE)
    assert url and url.group(1).strip(), (profile, "ETHERSCAN_VERIFIER_URL 为空")
    assert skip, (profile, "缺少 VERIFY_SKIP_CHAIN_IDS")
    skipped = {item.strip() for item in skip.group(1).split(",") if item.strip()}
    assert not skipped & {"56", "97"}, (profile, sorted(skipped))


def main():
    params_shared_copy()
    params_loader_cases()
    params_unset_coverage()
    params_required_consistency()
    verifier_skip_never_production()
    group_chat = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="group-chat-deploy-test-") as directory:
        root = Path(directory)
        deploy = root / "script/deploy"
        shutil.copytree(group_chat / "script/deploy", deploy)
        network = root / "script/network/test"
        network.mkdir(parents=True)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        for tool in ("cast", "forge", "osascript", "mktemp"):
            stub = bin_dir / tool
            stub.write_text("#!/bin/sh\nexec " + shlex.quote(sys.executable) + " "
                            + shlex.quote(str(Path(__file__).resolve())) + " --fake " + tool + ' "$@"\n')
            stub.chmod(0o755)
        addresses = {field: f"0x{index + 10:040x}" for index, field in enumerate(ADDRESS_FIELDS)}
        data_path, log_path = root / "rpc.json", root / "calls.log"
        tmp_dir = root / "tmp"
        tmp_dir.mkdir()
        data_path.write_text(
            json.dumps({
                "chain_id": "31337",
                "addresses": addresses,
                "core": CORE_ADDRESSES,
                "type_codes": {addresses[field]: code for field, code in MANAGER_TYPE_CODES.items()},
            }))
        network.joinpath("network.params").write_text("CHAIN_ID=31337\nRPC_URL=http://invalid.local\n")
        network.parent.joinpath("verifier.params").write_text(
            "ETHERSCAN_VERIFIER_URL=https://api.etherscan.io/v2/api\nVERIFY_SKIP_CHAIN_IDS=31337\n")
        network.joinpath("addresses.core.params").write_text(
            "".join(f"{field}={value}\n" for field, value in CORE_ADDRESSES.items()))
        network.joinpath("addresses.action.params").write_text(
            "".join(f"{field}={value}\n" for field, value in ACTION_ADDRESSES.items()))
        network.joinpath("group-chat.params").write_text(
            "GROUP_CHAT_ACTION_RECENT_ROUNDS=1\n"
            "GROUP_CHAT_MAX_ADMIN_IDS=1\n"
            "GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_MULTIPLIER=1\n"
            "GROUP_CHAT_BAN_THRESHOLD_RATIO=1\n"
            "GROUP_CHAT_BEFORE_POST_PLUGIN_ADDRESS=0x" + "0" * 40 + "\n"
            "GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS=0x" + "0" * 40 + "\n")
        saved = network / "addresses.group-chat.params"
        broadcast = root / "broadcast/DeployGroupChat.s.sol/31337/run-latest.json"
        broadcast.parent.mkdir(parents=True)
        broadcast.write_text(json.dumps({"timestamp": 0}, indent=2))
        base = {"PATH": str(bin_dir) + os.pathsep + os.environ["PATH"], "MOCK_DATA": str(data_path),
                "MOCK_LOG": str(log_path), "MOCK_BROADCAST": str(broadcast), "MOCK_TMP": str(tmp_dir)}
        checks = 0

        def write_account(password_line=""):
            network.joinpath(".account").write_text(
                "KEYSTORE_ACCOUNT=test-keystore\nACCOUNT_ADDRESS=0x" + "f5" * 20 + "\n" + password_line)

        def run(script, success=True, args=("test",), **extra):
            nonlocal checks
            log_path.write_text("")
            result = subprocess.run(["bash", str(deploy / script), *args], env={**base, **extra},
                                    text=True, capture_output=True)
            assert (result.returncode == 0) == success, (script, extra, result.stdout, result.stderr)
            output = result.stdout + result.stderr
            assert SECRET_PASSWORD not in output
            for marker in ("CREDENTIAL_IN_ARGV", "PASSWORD_FILE_MISSING"):
                assert marker not in output, (marker, output)
            log = [json.loads(line) for line in log_path.read_text().splitlines()]
            for call in log:
                if call[:2] == ["forge", "script"] and "--password-file" in call:
                    assert not Path(call[call.index("--password-file") + 1]).exists(), call
            checks += 1
            return result, log

        def forge_script_call(log):
            return next(call for call in log if call[:2] == ["forge", "script"])

        def kept_log_from(output):
            assert "Deployment log:" in output, output
            path = Path(output.split("Deployment log:", 1)[1].splitlines()[0].strip())
            assert path.exists(), path
            return path

        def assert_success_writes_all():
            write_account()
            result, log = run("11_deploy.sh")
            command = forge_script_call(log)
            assert "--password-file" in command and "--password" not in command, command
            output = result.stdout + result.stderr
            assert "PASSWORD_MODE=600" in output, output
            assert "PASSWORD_SHA=" + hashlib.sha256(b"test-password").hexdigest() in output, output
            assert len([call for call in log if call[0] == "osascript"]) == 1, log
            # 部署期静态校验（依赖绑定、名称空间、参数范围）在 DeployGroupChat.s.sol 的广播前阶段，
            # 11_deploy.sh 不再重复 cast 校验。
            assert not any(call[:2] == ["cast", "call"] for call in log), log
            text = saved.read_text()
            assert all(field + "=" + value in text for field, value in addresses.items()), text
            assert not list(tmp_dir.iterdir()), list(tmp_dir.iterdir())

        def assert_account_password():
            write_account("KEYSTORE_PASSWORD=" + SECRET_PASSWORD + "\n")
            result, log = run("11_deploy.sh")
            output = result.stdout + result.stderr
            assert "PASSWORD_SHA=" + hashlib.sha256(SECRET_PASSWORD.encode()).hexdigest() in output, output
            assert not any(call[0] == "osascript" for call in log), log
            assert not list(tmp_dir.iterdir()), list(tmp_dir.iterdir())

        def assert_empty_password_prompts():
            write_account("KEYSTORE_PASSWORD=\n")
            result, log = run("11_deploy.sh")
            output = result.stdout + result.stderr
            assert "PASSWORD_SHA=" + hashlib.sha256(b"test-password").hexdigest() in output, output
            assert len([call for call in log if call[0] == "osascript"]) == 1, log

        def assert_pre_broadcast_failure_is_quiet():
            saved.write_text("# previous deployment\n")
            params = network / "group-chat.params"
            params_text = params.read_text()
            params.unlink()
            try:
                result, log = run("11_deploy.sh", False)
            finally:
                params.write_text(params_text)
            output = result.stdout + result.stderr
            assert "Missing required configuration" in output, output
            assert "contracts may already be on chain" not in output, output
            assert "Deployment log:" not in output, output
            assert not any(call[:2] == ["forge", "script"] for call in log), log
            assert saved.read_text() == "# previous deployment\n"
            assert not list(tmp_dir.iterdir()), list(tmp_dir.iterdir())

        def assert_broadcast_failure_keeps_log():
            saved.write_text("# previous deployment\n")
            result, _ = run("11_deploy.sh", False, DEPLOY_FAIL="1")
            output = result.stdout + result.stderr
            assert "contracts may already be on chain" in output, output
            kept = kept_log_from(output)
            assert list(tmp_dir.iterdir()) == [kept], (list(tmp_dir.iterdir()), kept)
            assert saved.read_text() == "# previous deployment\n"
            kept.unlink()

        def assert_address_omission_keeps_log():
            saved.write_text("# previous deployment\n")
            result, _ = run("11_deploy.sh", False, OMIT_ADDRESS="GROUP_CHAT_ADDRESS")
            output = result.stdout + result.stderr
            assert "GROUP_CHAT_ADDRESS" in output, output
            assert "contracts may already be on chain" in output, output
            kept = kept_log_from(output)
            assert list(tmp_dir.iterdir()) == [kept], (list(tmp_dir.iterdir()), kept)
            assert saved.read_text() == "# previous deployment\n"
            kept.unlink()

        def assert_one_click_backup_cleanup():
            saved.write_text("# previous deployment\n")
            params = network / "group-chat.params"
            params_text = params.read_text()
            params.unlink()
            try:
                result, log = run("one_click_deploy.sh", False)
            finally:
                params.write_text(params_text)
            assert saved.read_text() == "# previous deployment\n"
            assert not any(call[:2] == ["forge", "script"] for call in log), log
            assert not list(tmp_dir.iterdir()), list(tmp_dir.iterdir())

        def assert_one_click_broadcast_failure_cleanup():
            saved.write_text("# previous deployment\n")
            result, _ = run("one_click_deploy.sh", False, DEPLOY_FAIL="1")
            output = result.stdout + result.stderr
            kept = kept_log_from(output)
            assert list(tmp_dir.iterdir()) == [kept], (list(tmp_dir.iterdir()), kept)
            assert saved.read_text() == "# previous deployment\n"
            kept.unlink()

        def assert_address_file_write_failure_is_atomic():
            saved.write_text("# previous deployment\n")
            network.chmod(0o555)
            try:
                result, _ = run("11_deploy.sh", False)
            finally:
                network.chmod(0o755)
            output = result.stdout + result.stderr
            assert "contracts may already be on chain" in output, output
            assert saved.read_text() == "# previous deployment\n"
            kept = kept_log_from(output)
            kept.unlink()
            assert not list(tmp_dir.iterdir()), list(tmp_dir.iterdir())

        def assert_stale_address_temp_cleanup():
            saved.write_text("# previous deployment\n")
            stale = network / ".addresses.group-chat.params.999"
            stale.write_text("partial")
            params = network / "group-chat.params"
            params_text = params.read_text()
            params.unlink()
            try:
                run("11_deploy.sh", False)
            finally:
                params.write_text(params_text)
            assert not stale.exists(), stale
            assert saved.read_text() == "# previous deployment\n"
            assert not list(tmp_dir.iterdir()), list(tmp_dir.iterdir())

        def assert_one_click_check_failure_recovery():
            saved.write_text("# previous deployment\n")
            # 21_check 的其余 getter 在假工具里返回零值，制造校验失败以触发回滚分支。
            result, _ = run("one_click_deploy.sh", False)
            output = result.stdout + result.stderr
            assert "New deployment addresses" in output, output
            assert "GROUP_CHAT_ADDRESS=" in output, output
            assert "Broadcast artifact:" in output, output
            assert "The previously saved addresses were restored." in output, output
            for field, code in MANAGER_TYPE_CODES.items():
                assert f"{field.removesuffix('_ADDRESS')}: TYPE_CODE '{code}' fits MAX_NAME_LENGTH" in output, output
            assert saved.read_text() == "# previous deployment\n"
            assert not list(tmp_dir.iterdir()), list(tmp_dir.iterdir())

        def assert_one_click_check_failure_without_old_file():
            saved.unlink(missing_ok=True)
            result, _ = run("one_click_deploy.sh", False)
            output = result.stdout + result.stderr
            assert "New deployment addresses" in output, output
            assert "No previous address file existed; the new address file was removed." in output, output
            assert not saved.exists()
            assert not list(tmp_dir.iterdir()), list(tmp_dir.iterdir())

        def assert_plugin_keys_required():
            # 插件槽位缺键即失败：不能把「没配」当成「未挂载」，否则拼错键名会静默部署出无插件的群。
            saved.write_text("# previous deployment\n")
            params = network / "group-chat.params"
            params_text = params.read_text()
            params.write_text("".join(line for line in params_text.splitlines(True)
                                      if not line.startswith("GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS=")))
            try:
                result, log = run("11_deploy.sh", False)
                output = result.stdout + result.stderr
                assert "GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS must be set" in output, output
                assert not any(call[:2] == ["forge", "script"] for call in log), log
                assert saved.read_text() == "# previous deployment\n"
                # 调用方环境里的同名变量不得补位：参数只认 group-chat.params。
                result, log = run("11_deploy.sh", False, GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS="0x" + "11" * 20)
                output = result.stdout + result.stderr
                assert "GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS must be set" in output, output
                assert not any(call[:2] == ["forge", "script"] for call in log), log
                assert saved.read_text() == "# previous deployment\n"
                # 键存在但值为空与缺键同罪：不能把空串留给 vm.envAddress 才报错。
                params.write_text("".join(
                    "GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS=\n"
                    if line.startswith("GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS=") else line
                    for line in params_text.splitlines(True)))
                result, log = run("11_deploy.sh", False)
                output = result.stdout + result.stderr
                assert "GROUP_CHAT_AFTER_POST_PLUGIN_ADDRESS must be set to a non-empty value" in output, output
                assert not any(call[:2] == ["forge", "script"] for call in log), log
                assert saved.read_text() == "# previous deployment\n"
            finally:
                params.write_text(params_text)

        cases = [
            ("01 成功：12 键写盘、密码临时文件 600 且清理", assert_success_writes_all),
            ("02 .account 密码直接使用，不弹窗", assert_account_password),
            ("03 空密码仍只弹一次窗", assert_empty_password_prompts),
            ("04 广播前失败：不误报已上链、不留日志", assert_pre_broadcast_failure_is_quiet),
            ("05 广播失败：保留日志并打印路径", assert_broadcast_failure_keeps_log),
            ("06 广播后缺地址：保留日志、不写半截文件", assert_address_omission_keeps_log),
            ("07 一键入口：广播前失败清理备份文件", assert_one_click_backup_cleanup),
            ("08 一键入口：广播失败只保留日志，备份已清理", assert_one_click_broadcast_failure_cleanup),
            ("09 地址文件写失败不截断旧记录（临时文件 + mv）", assert_address_file_write_failure_is_atomic),
            ("10 上次异常退出遗留的地址临时文件在启动时清理", assert_stale_address_temp_cleanup),
            ("11 一键入口：21 失败时打印新地址并恢复旧记录", assert_one_click_check_failure_recovery),
            ("12 一键入口：21 失败且无旧文件时删除新文件", assert_one_click_check_failure_without_old_file),
            ("13 插件槽位缺键即失败，不按未挂载兜底", assert_plugin_keys_required),
        ]
        failed = 0
        for name, body in cases:
            try:
                body()
                print("PASS  " + name)
            except AssertionError as error:
                failed += 1
                print("FAIL  " + name + "\n      " + str(error).replace("\n", " | ")[:900])
        print(f"# {len(cases) - failed}/{len(cases)} cases passed")
        return 1 if failed else 0


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--fake":
        sys.exit(fake_tool(sys.argv[2], sys.argv[3:]))
    sys.exit(main())
