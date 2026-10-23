#!/usr/bin/env python3
"""Group-chat deployment regression checks with stubbed cast/forge/osascript.

临时工程根里放三个同名假命令，脚本调用被记入日志，再断言退出码、地址文件、
密码临时文件（内容/权限/清理）与广播失败时的日志保留行为。不碰真仓库、不碰真链。
"""
import hashlib
import json
import os
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

SECRET_PASSWORD = "do-not-print-this-password"

ADDRESS_FIELDS = [
    "GROUP_CHAT_DELEGATE_ADDRESS",
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
            if os.environ.get("RPC_CODE_ERROR"):
                return 1
            print("0x01")
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
        for field, value in data["addresses"].items():
            if field != os.environ.get("OMIT_ADDRESS"):
                print(field + "= " + value)
    else:
        raise AssertionError(args)
    return 0


def main():
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
        data_path.write_text(json.dumps({"chain_id": "31337", "addresses": addresses}))
        network.joinpath("network.params").write_text("CHAIN_ID=31337\nRPC_URL=http://invalid.local\n")
        network.joinpath("addresses.core.params").write_text(
            "MEMBER_NFT_ADDRESS=0x" + "11" * 20 + "\nPHASE_ADDRESS=0x" + "22" * 20 + "\n")
        network.joinpath("addresses.action.params").write_text(
            "ACTION_TARGET_ADDRESS=0x" + "33" * 20 + "\nGROUP_ACTION_EXECUTOR_ADDRESS=0x" + "44" * 20 + "\n")
        network.joinpath("group-chat.params").write_text(
            "GROUP_CHAT_ACTION_RECENT_ROUNDS=1\n"
            "GROUP_CHAT_MAX_CONTENT_LENGTH=1\n"
            "GROUP_CHAT_MAX_MENTIONED_SENDER_IDS=1\n"
            "GROUP_CHAT_MAX_ADMIN_IDS=1\n"
            "GROUP_CHAT_MIN_SUPPORT_TO_OPPOSE_MULTIPLIER=1\n"
            "GROUP_CHAT_BAN_THRESHOLD_RATIO=1\n")
        saved = network / "addresses.group-chat.params"
        base = {"PATH": str(bin_dir) + os.pathsep + os.environ["PATH"], "MOCK_DATA": str(data_path),
                "MOCK_LOG": str(log_path), "MOCK_TMP": str(tmp_dir)}
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
            result, log = run("11_deploy.sh", False, RPC_CODE_ERROR="1")
            output = result.stdout + result.stderr
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
            result, log = run("one_click_deploy.sh", False, RPC_CODE_ERROR="1")
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
            run("11_deploy.sh", False, RPC_CODE_ERROR="1")
            assert not stale.exists(), stale
            assert saved.read_text() == "# previous deployment\n"
            assert not list(tmp_dir.iterdir()), list(tmp_dir.iterdir())

        def assert_one_click_check_failure_recovery():
            saved.write_text("# previous deployment\n")
            # 21_check 的 cast call 未在假工具里实现：11 成功后 21 失败，触发回滚分支。
            result, _ = run("one_click_deploy.sh", False)
            output = result.stdout + result.stderr
            assert "New deployment addresses" in output, output
            assert "GROUP_CHAT_ADDRESS=" in output, output
            assert "Broadcast artifact:" in output, output
            assert "The previously saved addresses were restored." in output, output
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

        cases = [
            ("01 成功：13 键写盘、密码临时文件 600 且清理", assert_success_writes_all),
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
