from __future__ import annotations

import base64
import io
import importlib.machinery
import importlib.util
import json
import os
import sys
import tempfile
import tomllib
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timezone
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "bin" / "codex-account"
loader = importlib.machinery.SourceFileLoader("codex_account", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
assert spec is not None
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
loader.exec_module(module)


def fake_jwt(payload: dict[str, object]) -> str:
    encoded = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
    return f"header.{encoded}.signature"


class CodexAccountTests(unittest.TestCase):
    def setUp(self) -> None:
        self.original_account = os.environ.pop("CODEX_ACCOUNT", None)
        self.temp_dir = tempfile.TemporaryDirectory()
        root = Path(self.temp_dir.name)
        self.personal = module.Account("personal", "Personal", root / "personal")
        self.work = module.Account("work", "Work", root / "work-home")
        self.config = module.Config(
            path=root / "config.toml",
            default_account="personal",
            announce=False,
            codex_binary=root / "codex",
            shared_home=root / "personal",
            accounts={"personal": self.personal, "work": self.work},
            paths={root / "projects": "work", root / "projects" / "personal": "personal"},
        )

    def tearDown(self) -> None:
        self.temp_dir.cleanup()
        if self.original_account is not None:
            os.environ["CODEX_ACCOUNT"] = self.original_account

    def test_longest_path_rule_wins(self) -> None:
        root = Path(self.temp_dir.name)
        account, matched = module.select_account(
            self.config, root / "projects" / "personal" / "repo"
        )
        self.assertEqual(account.name, "personal")
        self.assertEqual(matched, root / "projects" / "personal")

    def test_path_prefix_collision_does_not_match(self) -> None:
        root = Path(self.temp_dir.name)
        account, matched = module.select_account(self.config, root / "projects-evil" / "repo")
        self.assertEqual(account.name, "personal")
        self.assertIsNone(matched)

    def test_codex_cd_argument_is_used(self) -> None:
        root = Path(self.temp_dir.name)
        selected = module.target_directory(["exec", "-C", str(root / "projects"), "hello"])
        self.assertEqual(selected, (root / "projects").resolve(strict=False))

    def test_auth_inspection_never_returns_token_values(self) -> None:
        self.work.home.mkdir(parents=True)
        expires = int(datetime.now(timezone.utc).timestamp()) + 3600
        auth = {
            "auth_mode": "chatgpt",
            "last_refresh": datetime.now(timezone.utc).isoformat(),
            "tokens": {
                "access_token": fake_jwt({"exp": expires}),
                "id_token": fake_jwt({"exp": expires}),
                "refresh_token": "top-secret-refresh-token",
                "account_id": "top-secret-account-id",
            },
        }
        auth_path = self.work.home / "auth.json"
        auth_path.write_text(json.dumps(auth), encoding="utf-8")
        auth_path.chmod(0o600)

        inspected = module.inspect_auth(self.work)

        self.assertFalse(inspected["access_expired"])
        self.assertTrue(inspected["refresh_token_present"])
        serialized = json.dumps(inspected)
        self.assertNotIn("top-secret-refresh-token", serialized)
        self.assertNotIn("top-secret-account-id", serialized)

    def test_create_account_and_add_path_mapping(self) -> None:
        root = Path(self.temp_dir.name)
        config_path = root / "accounts.toml"
        config_path.write_text(
            "\n".join(
                (
                    "version = 1",
                    'default_account = "personal"',
                    'codex_binary = "/bin/true"',
                    f'shared_home = {json.dumps(str(root / "personal"))}',
                    "",
                    "[accounts.personal]",
                    'label = "Personal"',
                    f'home = {json.dumps(str(root / "personal"))}',
                    "",
                    "[paths]",
                    "",
                )
            ),
            encoding="utf-8",
        )

        old_config = os.environ.get("CODEX_ACCOUNTS_CONFIG")
        os.environ["CODEX_ACCOUNTS_CONFIG"] = str(config_path)
        try:
            config = module.load_config()
            config, account = module.create_account(config, "customer-one", "Customer One")
            config = module.add_path_mapping(config, account, str(root / "customer"))
        finally:
            if old_config is None:
                os.environ.pop("CODEX_ACCOUNTS_CONFIG", None)
            else:
                os.environ["CODEX_ACCOUNTS_CONFIG"] = old_config

        parsed = tomllib.loads(config_path.read_text(encoding="utf-8"))
        self.assertEqual(parsed["accounts"]["customer-one"]["label"], "Customer One")
        self.assertEqual(parsed["paths"][str(root / "customer")], "customer-one")
        self.assertTrue((root / "personal" / "auth-customer-one").is_dir())

    def test_shell_init_uses_sibling_wrapper(self) -> None:
        expected = SCRIPT.resolve(strict=False).with_name("codex")
        output = io.StringIO()
        with redirect_stdout(output):
            self.assertEqual(module.command_shell_init(), 0)

        self.assertEqual(output.getvalue(), f'codex() {{ command {expected} "$@"; }}\n')


if __name__ == "__main__":
    unittest.main()
