#!/usr/bin/env bash

set -euo pipefail

repository_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "${test_root}"' EXIT

fake_codex="${test_root}/real-codex"
cat >"${fake_codex}" <<'EOF'
#!/usr/bin/env bash
printf 'CODEX_HOME=%s\n' "${CODEX_HOME-}"
printf 'ARGS=%s\n' "$*"
EOF
chmod 0755 "${fake_codex}"

test_home="${test_root}/home"
install_prefix="${test_root}/prefix"
config_path="${test_root}/config/config.toml"
mkdir -p "${test_home}" "${install_prefix}/bin"
ln -s "${fake_codex}" "${install_prefix}/bin/codex"

HOME="${test_home}" SHELL=/bin/bash \
  "${repository_dir}/install.sh" \
  --prefix "${install_prefix}" \
  --config "${config_path}" \
  --codex-binary "${fake_codex}" \
  --shell-hook >/dev/null

grep -F 'default_account = "default"' "${config_path}" >/dev/null
grep -F '# >>> codex-account-manager >>>' "${test_home}/.bashrc" >/dev/null
test ! -L "${install_prefix}/bin/codex"
backup_link="$(find "${install_prefix}/share/codex-account/backups" -type l -name 'codex.*' -print -quit)"
test -n "${backup_link}"
test "$(readlink -- "${backup_link}")" = "${fake_codex}"

output="$({
  env -u CODEX_ACCOUNT HOME="${test_home}" CODEX_ACCOUNTS_CONFIG="${config_path}" \
    "${install_prefix}/bin/codex" --version
} 2>/dev/null)"
grep -F "CODEX_HOME=${test_home}/.codex" <<<"${output}" >/dev/null
grep -F 'ARGS=-c cli_auth_credentials_store="file" --version' <<<"${output}" >/dev/null

printf '\n# keep-me\n' >>"${config_path}"
HOME="${test_home}" \
  "${repository_dir}/install.sh" \
  --prefix "${install_prefix}" \
  --config "${config_path}" \
  --codex-binary "${fake_codex}" >/dev/null
grep -F '# keep-me' "${config_path}" >/dev/null

echo "installer smoke test: ok"
