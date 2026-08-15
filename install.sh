#!/usr/bin/env bash

set -euo pipefail

repository_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
install_prefix="${PREFIX:-${HOME}/.local}"
config_path="${CODEX_ACCOUNTS_CONFIG:-${HOME}/.config/codex-accounts/config.toml}"
codex_binary="${CODEX_ACCOUNT_REAL_CODEX:-}"
install_shell_hook=false

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --prefix DIR          インストール先（既定: ~/.local）
  --config FILE         設定ファイル（既定: ~/.config/codex-accounts/config.toml）
  --codex-binary FILE   Codex CLI本体のパス（通常は自動検出）
  --shell-hook          ~/.bashrc または ~/.zshrc にルーターを有効化する行を追加
  -h, --help            このヘルプを表示
EOF
}

while (($#)); do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || { echo "install: --prefix requires a value" >&2; exit 2; }
      install_prefix="$2"
      shift 2
      ;;
    --config)
      [[ $# -ge 2 ]] || { echo "install: --config requires a value" >&2; exit 2; }
      config_path="$2"
      shift 2
      ;;
    --codex-binary)
      [[ $# -ge 2 ]] || { echo "install: --codex-binary requires a value" >&2; exit 2; }
      codex_binary="$2"
      shift 2
      ;;
    --shell-hook)
      install_shell_hook=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "install: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "install: Python 3.11以降が必要です" >&2
  exit 1
fi

if ! python3 -c 'import sys, tomllib; raise SystemExit(sys.version_info < (3, 11))'; then
  echo "install: Python 3.11以降が必要です" >&2
  exit 1
fi

if [[ -z "${codex_binary}" ]]; then
  codex_binary="$(command -v codex || true)"
fi
if [[ -z "${codex_binary}" || ! -x "${codex_binary}" ]]; then
  echo "install: Codex CLI本体を検出できません" >&2
  echo "install: --codex-binary /path/to/codex を指定してください" >&2
  exit 1
fi

bin_dir="${install_prefix}/bin"
manager_target="${bin_dir}/codex-account"
wrapper_target="${bin_dir}/codex"

if [[ "${codex_binary}" == "${wrapper_target}" ]]; then
  echo "install: 検出したcodexはインストール先のラッパーです" >&2
  echo "install: --codex-binary でCodex CLI本体を明示してください" >&2
  exit 1
fi

config_dir="$(dirname -- "${config_path}")"
mkdir -p "${bin_dir}"
if [[ ! -d "${config_dir}" ]]; then
  mkdir -p "${config_dir}"
  chmod 0700 "${config_dir}"
fi

backup_dir="${install_prefix}/share/codex-account/backups"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
for target in "${manager_target}" "${wrapper_target}"; do
  source_file="${repository_dir}/bin/$(basename -- "${target}")"
  if [[ -L "${target}" ]] || { [[ -e "${target}" ]] && ! cmp -s "${source_file}" "${target}"; }; then
    mkdir -p "${backup_dir}"
    chmod 0700 "${backup_dir}"
    cp -pP -- "${target}" "${backup_dir}/$(basename -- "${target}").${timestamp}"
    echo "backup: ${target}"
  fi
  if [[ -L "${target}" ]]; then
    unlink -- "${target}"
  fi
done

install -m 0755 "${repository_dir}/bin/codex-account" "${manager_target}"
install -m 0755 "${repository_dir}/bin/codex" "${wrapper_target}"

if [[ ! -e "${config_path}" ]]; then
  python3 - "${repository_dir}/config/config.example.toml" "${config_path}" "${codex_binary}" <<'PY'
import json
import os
import pathlib
import sys

template_path = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
codex_binary = str(pathlib.Path(sys.argv[3]).expanduser().absolute())
text = template_path.read_text(encoding="utf-8")
text = text.replace('"@CODEX_BINARY@"', json.dumps(codex_binary, ensure_ascii=False))
temporary = destination.with_name(f".{destination.name}.tmp-{os.getpid()}")
temporary.write_text(text, encoding="utf-8")
temporary.chmod(0o600)
os.replace(temporary, destination)
PY
  echo "created: ${config_path}"
else
  echo "kept: ${config_path}"
fi

if [[ "${install_shell_hook}" == true ]]; then
  shell_name="$(basename -- "${SHELL:-bash}")"
  if [[ "${shell_name}" == "zsh" ]]; then
    shell_rc="${HOME}/.zshrc"
  else
    shell_rc="${HOME}/.bashrc"
  fi
  python3 - "${shell_rc}" "${manager_target}" <<'PY'
import pathlib
import shlex
import sys

rc_path = pathlib.Path(sys.argv[1])
manager = shlex.quote(sys.argv[2])
begin = "# >>> codex-account-manager >>>"
end = "# <<< codex-account-manager <<<"
block = f'{begin}\neval "$(%s shell-init)"\n{end}' % manager
current = rc_path.read_text(encoding="utf-8") if rc_path.exists() else ""
start = current.find(begin)
finish = current.find(end, start + len(begin)) if start >= 0 else -1
if start >= 0 and finish >= 0:
    finish += len(end)
    suffix = current[finish:].lstrip("\n")
    updated = current[:start].rstrip() + "\n\n" + block + "\n"
    if suffix:
        updated += suffix
else:
    updated = current.rstrip() + "\n\n" + block + "\n"
rc_path.write_text(updated, encoding="utf-8")
PY
  echo "shell hook: ${shell_rc}"
fi

echo
echo "installed: ${manager_target}"
echo "wrapper:   ${wrapper_target}"
echo "config:    ${config_path}"
echo
echo "次の確認コマンド:"
echo "  ${manager_target} list"
echo "  ${manager_target} add work --path \"${HOME}/src/work\""
if [[ "${install_shell_hook}" == false ]]; then
  echo
  echo "PATH上で別のcodexが優先される場合は、次をシェル設定へ追加してください:"
  printf '  eval "$(%q shell-init)"\n' "${manager_target}"
fi
