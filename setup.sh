#!/usr/bin/env bash
set -euo pipefail

INSTALL_DOCS=0
INSTALL_CMSIS=0
INSTALL_PICO_SDK=0
CHECK_ONLY=0
NATIVE_BUILD=0

usage() {
    cat <<'EOF'
Usage: ./setup.sh [options]

Bootstraps project-local MMCU tooling and reports missing host tools.
This script does not install OS packages with apt/dnf/brew/pacman.

Default action:
  - check required host tools
  - create/update ./venv
  - install requirements-yaml.txt for the configure-time YAML resolver

Options:
      --docs          Also install documentation tooling from requirements-docs.txt
      --cmsis         Also run platforms/cmsis/cmsis-install.sh
      --pico-sdk      Also run platforms/pico-sdk/pico-sdk-install.sh
      --native-build  Configure and build the default native target as a smoke test
      --check         Report tool status only; make no changes
  -h, --help          Show this help

Examples:
  ./setup.sh
  ./setup.sh --docs
  ./setup.sh --cmsis
  ./setup.sh --pico-sdk
  ./setup.sh --check
  ./setup.sh --native-build
EOF
}

info() {
    echo "==> $*"
}

warn() {
    echo "Warning: $*" >&2
}

fail() {
    echo "Error: $*" >&2
    exit 1
}

have_command() {
    command -v "$1" >/dev/null 2>&1
}

require_command() {
    local command_name="$1" purpose="$2"
    if have_command "$command_name"; then
        echo "ok: $command_name ($purpose)"
    else
        echo "missing: $command_name ($purpose)"
        return 1
    fi
}

check_cmake_version() {
    local version
    require_command cmake "CMake 4.0+ configure/build" || return 1
    version="$(cmake --version | awk 'NR==1 {print $3}')"
    if [[ "$(printf '%s\n' "4.0.0" "$version" | sort -V | head -n1)" != "4.0.0" ]]; then
        echo "missing: cmake 4.0+ (found $version)"
        return 1
    fi
    echo "ok: cmake $version"
}

check_compiler() {
    local c_ok=0 cxx_ok=0
    if have_command cc || have_command gcc || have_command clang; then
        c_ok=1
        echo "ok: C compiler"
    else
        echo "missing: C compiler"
    fi
    if have_command c++ || have_command g++ || have_command clang++; then
        cxx_ok=1
        echo "ok: C++ compiler"
    else
        echo "missing: C++ compiler with C++20 module support"
    fi
    [[ $c_ok -eq 1 && $cxx_ok -eq 1 ]]
}

check_host_tools() {
    local required_missing=0

    info "Checking required host tools"
    check_cmake_version || required_missing=1
    require_command python3 "project-local virtual environment and Python tooling" || required_missing=1
    check_compiler || required_missing=1

    if have_command ninja; then
        echo "ok: ninja (preferred CMake generator for C++20 modules)"
    else
        warn "ninja not found; C++20 modules require Ninja, Ninja Multi-Config, or a supported IDE generator"
    fi

    if [[ $INSTALL_CMSIS -eq 1 || $INSTALL_PICO_SDK -eq 1 ]]; then
        require_command git "vendored CMSIS or pico-sdk checkout" || required_missing=1
    elif have_command git; then
        echo "ok: git (needed when CMSIS or pico-sdk are fetched)"
    else
        warn "git not found; needed only when fetching CMSIS or pico-sdk"
    fi

    if [[ $required_missing -ne 0 ]]; then
        fail "Required host tools are missing. See docs/setup.md and docs/tools.md."
    fi
}

venv_python() {
    echo "./venv/bin/python"
}

check_python_package() {
    local python_bin="$1" import_name="$2" label="$3"
    if "$python_bin" -c "import ${import_name}" >/dev/null 2>&1; then
        echo "ok: $label"
    else
        echo "missing: $label"
        return 1
    fi
}

setup_venv() {
    local python_bin
    python_bin="$(venv_python)"

    if [[ $CHECK_ONLY -eq 1 ]]; then
        info "Checking Python virtual environment"
        if [[ ! -x "$python_bin" ]]; then
            echo "missing: ./venv"
            return 0
        fi
        check_python_package "$python_bin" yaml PyYAML || true
        if [[ $INSTALL_DOCS -eq 1 ]]; then
            check_python_package "$python_bin" mkdocs MkDocs || true
        fi
        return 0
    fi

    if [[ ! -x "$python_bin" ]]; then
        info "Creating ./venv"
        python3 -m venv ./venv
    fi

    info "Updating pip"
    "$python_bin" -m pip install --upgrade pip

    info "Installing YAML tooling"
    "$python_bin" -m pip install -r requirements-yaml.txt

    if [[ $INSTALL_DOCS -eq 1 ]]; then
        info "Installing documentation tooling"
        "$python_bin" -m pip install -r requirements-docs.txt
    fi

    check_python_package "$python_bin" yaml PyYAML
}

setup_pico_sdk() {
    if [[ $CHECK_ONLY -eq 1 ]]; then
        info "Checking pico-sdk checkout"
        if [[ -e platforms/pico-sdk/pico-sdk/pico_sdk_init.cmake ]]; then
            echo "ok: platforms/pico-sdk/pico-sdk"
        else
            echo "missing: platforms/pico-sdk/pico-sdk"
        fi
        return 0
    fi

    info "Installing vendored pico-sdk and platform-local tools"
    ./platforms/pico-sdk/pico-sdk-install.sh
}

setup_cmsis() {
    if [[ $CHECK_ONLY -eq 1 ]]; then
        info "Checking CMSIS_6 checkout"
        if [[ -e platforms/cmsis/CMSIS_6/CMSIS/Core/Include ]]; then
            echo "ok: platforms/cmsis/CMSIS_6"
        else
            echo "missing: platforms/cmsis/CMSIS_6"
        fi
        return 0
    fi

    info "Installing vendored CMSIS_6"
    ./platforms/cmsis/cmsis-install.sh
}

run_native_build() {
    if [[ $CHECK_ONLY -eq 1 ]]; then
        return 0
    fi

    info "Configuring native build"
    ./configure.sh --platform native
    info "Building native target"
    ./build.sh
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docs)
            INSTALL_DOCS=1
            shift
            ;;
        --cmsis)
            INSTALL_CMSIS=1
            shift
            ;;
        --pico-sdk)
            INSTALL_PICO_SDK=1
            shift
            ;;
        --native-build)
            NATIVE_BUILD=1
            shift
            ;;
        --check)
            CHECK_ONLY=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

check_host_tools
setup_venv

if [[ $INSTALL_CMSIS -eq 1 ]]; then
    setup_cmsis
fi

if [[ $INSTALL_PICO_SDK -eq 1 ]]; then
    setup_pico_sdk
fi

if [[ $NATIVE_BUILD -eq 1 ]]; then
    run_native_build
fi

if [[ $CHECK_ONLY -eq 1 ]]; then
    info "Check complete"
else
    info "Setup complete"
    echo "Next: ./configure.sh && ./build.sh"
fi
