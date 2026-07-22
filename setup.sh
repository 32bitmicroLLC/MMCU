#!/usr/bin/env bash
set -euo pipefail

INSTALL_DOCS=0
INSTALL_CMSIS=0
INSTALL_PICO_SDK=0
CHECK_ONLY=0
NATIVE_BUILD=0
FORCE_VENV=0
CLEAR_VENV=0
INSTALL_CLANG=0
CLANG_VERSION=21

usage() {
    cat <<'EOF'
Usage: ./setup.sh [options]

Bootstraps project-local MMCU tooling and reports missing host tools.
By default this script does not install OS packages. The explicit exception
is --install-clang, which uses apt.llvm.org on Debian/Ubuntu.

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
      --force         Repair/reinstall ./venv in place; with --install-clang,
                      install the requested Clang even if another usable
                      compiler exists
      --clear         Recreate ./venv from scratch before installing requirements
      --install-clang Install Clang from apt.llvm.org if no usable native compiler exists
      --clang-version <n>
                      LLVM/Clang major version for --install-clang (default: 21)
  -h, --help          Show this help

Examples:
  ./setup.sh
  ./setup.sh --docs
  ./setup.sh --cmsis
  ./setup.sh --pico-sdk
  ./setup.sh --check
  ./setup.sh --force
  ./setup.sh --clear
  ./setup.sh --install-clang
  ./setup.sh --install-clang --clang-version 21
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

version_at_least() {
    local required="$1" actual="$2"
    [[ -n "$actual" ]] || return 1
    [[ "$(printf '%s\n' "$required" "$actual" | sort -V | head -n1)" == "$required" ]]
}

native_cxx_candidate() {
    local candidate major
    if [[ -n "${CXX:-}" ]]; then
        echo "$CXX"
        return 0
    fi
    for major in 23 22 21 20 19 18 17 16 15; do
        candidate="g++-$major"
        have_command "$candidate" && command -v "$candidate" && return 0
    done
    for major in 23 22 21 20; do
        candidate="clang++-$major"
        have_command "$candidate" && command -v "$candidate" && return 0
    done
    for candidate in c++ g++ clang++; do
        have_command "$candidate" && command -v "$candidate" && return 0
    done
}

check_native_cxx_modules_compiler() {
    local cxx_path version_line version

    cxx_path="$(native_cxx_candidate)"
    if [[ -z "$cxx_path" ]]; then
        echo "missing: native C++20 module compiler (GCC 15+ or Clang 20+)"
        return 1
    fi

    version_line="$("$cxx_path" --version 2>/dev/null | head -1)"
    if [[ "$version_line" == *clang* || "$version_line" == *Clang* ]]; then
        version="$(printf '%s\n' "$version_line" | sed -E 's/.*version ([0-9]+([.][0-9]+)*).*/\1/')"
        if version_at_least "20.0.0" "$version"; then
            echo "ok: native C++20 module compiler (Clang $version)"
            return 0
        fi
        echo "missing: native C++20 module compiler requires Clang 20+ or GCC 15+ (found Clang $version at $cxx_path)"
        return 1
    fi

    version="$("$cxx_path" -dumpfullversion -dumpversion 2>/dev/null | head -1)"
    if version_at_least "15.0.0" "$version"; then
        echo "ok: native C++20 module compiler (GCC $version)"
        return 0
    fi

    echo "missing: native C++20 module compiler requires GCC 15+ or Clang 20+ (found GNU $version at $cxx_path)"
    return 1
}

usable_native_cxx_modules_compiler() {
    check_native_cxx_modules_compiler >/dev/null 2>&1
}

install_clang_toolchain() {
    local tmp_dir llvm_script clang_bin clangxx_bin

    if [[ $CHECK_ONLY -eq 1 ]]; then
        return 0
    fi

    if usable_native_cxx_modules_compiler && [[ $FORCE_VENV -eq 0 ]]; then
        info "Usable native C++20 module compiler already installed; skipping Clang install"
        return 0
    fi

    if ! have_command apt-get; then
        fail "--install-clang is only supported on apt-based Debian/Ubuntu systems. Install GCC 15+ or Clang 20+ manually."
    fi
    if ! have_command wget; then
        fail "--install-clang requires wget to download https://apt.llvm.org/llvm.sh"
    fi
    if ! have_command sudo; then
        fail "--install-clang requires sudo because apt.llvm.org installs OS packages"
    fi
    if [[ ! "$CLANG_VERSION" =~ ^[0-9]+$ ]] || (( CLANG_VERSION < 20 )); then
        fail "--clang-version must be an integer >= 20"
    fi

    tmp_dir="$(mktemp -d)"
    info "Downloading apt.llvm.org installer"
    wget -O "$tmp_dir/llvm.sh" https://apt.llvm.org/llvm.sh
    chmod +x "$tmp_dir/llvm.sh"

    info "Installing Clang $CLANG_VERSION through apt.llvm.org"
    sudo "$tmp_dir/llvm.sh" "$CLANG_VERSION"

    clang_bin="/usr/bin/clang-$CLANG_VERSION"
    clangxx_bin="/usr/bin/clang++-$CLANG_VERSION"
    if [[ ! -x "$clang_bin" || ! -x "$clangxx_bin" ]]; then
        fail "Expected $clang_bin and $clangxx_bin after installation, but one is missing"
    fi

    info "Installed Clang toolchain"
    "$clangxx_bin" --version | head -1
    echo "Use: CC=$clang_bin CXX=$clangxx_bin ./configure.sh --clean"
}

check_ninja_version() {
    local version
    require_command ninja "CMake C++20 module generator" || return 1
    version="$(ninja --version 2>/dev/null | head -1)"
    if [[ "$(printf '%s\n' "1.11.0" "$version" | sort -V | head -n1)" != "1.11.0" ]]; then
        echo "missing: ninja 1.11+ (found $version)"
        return 1
    fi
    echo "ok: ninja $version"
}

check_host_tools() {
    local required_missing=0

    info "Checking required host tools"
    check_cmake_version || required_missing=1
    require_command python3 "project-local virtual environment and Python tooling" || required_missing=1
    check_compiler || required_missing=1
    check_native_cxx_modules_compiler || required_missing=1
    check_ninja_version || required_missing=1

    if [[ $INSTALL_CMSIS -eq 1 || $INSTALL_PICO_SDK -eq 1 ]]; then
        require_command git "vendored CMSIS/DFP or pico-sdk checkout" || required_missing=1
    elif have_command git; then
        echo "ok: git (needed when CMSIS or pico-sdk are fetched)"
    else
        warn "git not found; needed only when fetching CMSIS/DFP or pico-sdk"
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

ensure_venv_pip() {
    local python_bin="$1"

    if "$python_bin" -m pip --version >/dev/null 2>&1; then
        return 0
    fi

    info "Bootstrapping pip in ./venv"
    if "$python_bin" -m ensurepip --upgrade >/dev/null 2>&1; then
        return 0
    fi

    fail "The existing ./venv has Python but no pip, and ensurepip is unavailable. Install your OS venv package (for example python3-venv/python3.10-venv on Debian/Ubuntu), then rerun ./setup.sh."
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
        if "$python_bin" -m pip --version >/dev/null 2>&1; then
            echo "ok: pip"
        else
            echo "missing: pip"
        fi
        check_python_package "$python_bin" yaml PyYAML || true
        if [[ $INSTALL_DOCS -eq 1 ]]; then
            check_python_package "$python_bin" mkdocs MkDocs || true
        fi
        return 0
    fi

    if [[ $CLEAR_VENV -eq 1 ]]; then
        info "Recreating ./venv"
        python3 -m venv --clear ./venv
    elif [[ $FORCE_VENV -eq 1 ]]; then
        if [[ -x "$python_bin" ]]; then
            info "Upgrading ./venv in place"
            python3 -m venv --upgrade ./venv
        else
            info "Creating ./venv"
            python3 -m venv ./venv
        fi
    elif [[ ! -x "$python_bin" ]]; then
        info "Creating ./venv"
        python3 -m venv ./venv
    fi

    ensure_venv_pip "$python_bin"

    info "Updating pip"
    "$python_bin" -m pip install --upgrade pip

    info "Installing YAML tooling"
    if [[ $FORCE_VENV -eq 1 ]]; then
        "$python_bin" -m pip install --upgrade --force-reinstall -r requirements-yaml.txt
    else
        "$python_bin" -m pip install -r requirements-yaml.txt
    fi

    if [[ $INSTALL_DOCS -eq 1 ]]; then
        info "Installing documentation tooling"
        if [[ $FORCE_VENV -eq 1 ]]; then
            "$python_bin" -m pip install --upgrade --force-reinstall -r requirements-docs.txt
        else
            "$python_bin" -m pip install -r requirements-docs.txt
        fi
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
        info "Checking CMSIS_6 and CMSIS-RP2xxx-DFP checkouts"
        if [[ -e platforms/cmsis/CMSIS_6/CMSIS/Core/Include ]]; then
            echo "ok: platforms/cmsis/CMSIS_6"
        else
            echo "missing: platforms/cmsis/CMSIS_6"
        fi
        if [[ -e platforms/cmsis/CMSIS-RP2xxx-DFP/CMSIS/Device/RP2040/Include/rp2040.h ]]; then
            echo "ok: platforms/cmsis/CMSIS-RP2xxx-DFP"
        else
            echo "missing: platforms/cmsis/CMSIS-RP2xxx-DFP"
        fi
        return 0
    fi

    info "Installing vendored CMSIS_6 and CMSIS-RP2xxx-DFP"
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
        --force)
            FORCE_VENV=1
            shift
            ;;
        --clear)
            CLEAR_VENV=1
            shift
            ;;
        --install-clang)
            INSTALL_CLANG=1
            shift
            ;;
        --clang-version)
            CLANG_VERSION="${2:-}"
            if [[ -z "$CLANG_VERSION" ]]; then
                echo "Error: --clang-version requires a value" >&2
                usage
                exit 1
            fi
            shift 2
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

if [[ $CHECK_ONLY -eq 1 && ( $FORCE_VENV -eq 1 || $CLEAR_VENV -eq 1 ) ]]; then
    fail "--check cannot be combined with --force or --clear"
fi

if [[ $CLEAR_VENV -eq 1 && $FORCE_VENV -eq 1 ]]; then
    FORCE_VENV=0
fi

if [[ $INSTALL_CLANG -eq 1 ]]; then
    install_clang_toolchain
fi

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
