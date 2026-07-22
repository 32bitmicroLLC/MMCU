#!/usr/bin/env bash
set -euo pipefail

PLATFORM="native"
TARGET=""
BOARD=""
COMPILER="gcc"
TOOLCHAIN_FILE=""
_mmcu_effective_target=""
CPU=""
CMSIS_DIR=""
CMSIS_GIT_TAG="v6.3.0"
CMSIS_RP2XXX_DFP_DIR=""
LINKER_MAP=0
ARM_GCC=""
ARM_GXX=""
CLANG_CC=""
CLANG_CXX=""
MMCU_CC=""
MMCU_CXX=""
APPLICATION_DIR=""
BUILD_DIR=""
BUILD_TYPE="Release"
GENERATOR=""
CLEAN=0
INTERACTIVE=0
VERBOSE=0
LIST_TOOLCHAINS=0

usage() {
    cat <<'EOF'
Usage: ./configure.sh [options]

Configures (but does not build) MMCU for a chosen platform/target/toolchain.
See docs/configure.md for the full MMCU_PLATFORM/MMCU_TARGET/toolchain model.

Options:
  -p, --platform <name>     MMCU_PLATFORM: native, mcu, cmsis, or pico_sdk (default: native)
  -t, --target <name>       MMCU_TARGET (default depends on --platform)
      --board <name>        MMCU_BOARD override (default depends on MMCU_TARGET)
      --compiler <name>     mcu/cmsis/pico_sdk platforms only: gcc or clang, selects
                             the default toolchain file (default: gcc)
      --toolchain-file <f>  Explicit CMAKE_TOOLCHAIN_FILE, overrides --compiler
      --cpu <cpu>           MMCU_CPU override (mcu/cmsis/pico_sdk, default target-derived)
      --cmsis-dir <path>    MMCU_CMSIS_DIR (cortex-m0, cortex-m0plus)
      --cmsis-git-tag <tag> MMCU_CMSIS_GIT_TAG (default: v6.3.0)
      --cmsis-rp2xxx-dfp-dir <path>
                             Raspberry Pi CMSIS-RP2xxx-DFP checkout
                             (cmsis + rp2040)
      --linker-map          Enable MMCU_LINKER_MAP (mmcu_app.map + --cref)
      --arm-gcc <path>      MMCU_ARM_GCC override
      --arm-gxx <path>      MMCU_ARM_GXX override
      --clang-cc <path>     MMCU_CLANG_CC override
      --clang-cxx <path>    MMCU_CLANG_CXX override
      --cc <path>           Native C compiler override recorded as MMCU_CC
      --cxx <path>          Native C++ compiler override recorded as MMCU_CXX
      --application-dir <d>  Application directory containing mmcu.yaml and main.cpp
                             (default: applications/main)
  -d, --build-dir <dir>     Build directory (default depends on platform/target)
  -b, --type <type>         CMAKE_BUILD_TYPE (default: Release)
  -G, --generator <name>    CMake generator (default: Ninja if available)
  -c, --clean               Remove build directory before configure
  -i, --interactive         Prompt with numbered choices instead of flags
      --list-toolchains     List discovered compiler toolchains for the selected
                             platform/target and exit
  -v, --verbose             Show verbose CMake configure output
  -h, --help                Show this help

Examples:
  ./configure.sh
  ./configure.sh --platform mcu --target cortex-m0
  ./configure.sh --platform cmsis --target cortex-m0
  ./configure.sh --platform cmsis --target rp2040 --board pico
  ./configure.sh --platform mcu --target cortex-m0plus --compiler clang
  ./configure.sh --platform mcu --target cortex-m0 --toolchain-file cmake/toolchains/arm-none-eabi-clang.cmake
  ./configure.sh --platform pico_sdk --target rp2040
  ./configure.sh --platform pico_sdk --target rp2040 --board pico-w
  ./configure.sh --application-dir applications/mcp/server --build-dir build-mcp-server-native
  ./configure.sh --interactive
EOF
}

# Prompts with a numbered menu. Args: question, default_index (1-based),
# option... Prints the menu to stderr, echoes the chosen 1-based index to
# stdout so callers can do: choice=$(prompt_choice "..." 1 "a" "b")
prompt_choice() {
    local question="$1" default="$2"
    shift 2
    local options=("$@")
    local i choice

    echo "$question" >&2
    for i in "${!options[@]}"; do
        printf '  %d) %s\n' "$((i + 1))" "${options[$i]}" >&2
    done

    while true; do
        read -r -p "Choice [$default]: " choice
        choice="${choice:-$default}"
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            echo "$choice"
            return 0
        fi
        echo "Invalid choice, enter a number from 1 to ${#options[@]}." >&2
    done
}

# Prompts for free text with a default. Args: question, default.
prompt_default() {
    local question="$1" default="$2" answer
    read -r -p "$question [$default]: " answer
    echo "${answer:-$default}"
}

# Prompts for yes/no. Args: question, default ("y" or "n"). Returns 0 for yes.
prompt_yes_no() {
    local question="$1" default="$2" answer suffix
    if [[ "$default" == "y" ]]; then suffix="[Y/n]"; else suffix="[y/N]"; fi
    read -r -p "$question $suffix: " answer
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy] ]]
}

list_applications() {
    local repo_root app_manifest app_dir app_name label
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    while IFS= read -r app_manifest; do
        app_dir="$(dirname "$app_manifest")"
        if [[ ! -f "$repo_root/$app_dir/main.cpp" ]]; then
            continue
        fi

        app_name="$(awk -F: '
            /^[[:space:]]*name[[:space:]]*:/ {
                value=$2
                sub(/^[[:space:]]*/, "", value)
                sub(/[[:space:]]*$/, "", value)
                print value
                exit
            }
        ' "$repo_root/$app_manifest")"
        label="$app_dir"
        [[ -n "$app_name" ]] && label="$label - $app_name"
        echo "$app_dir"$'\t'"$label"
    done < <(cd "$repo_root" && find applications -mindepth 2 -name mmcu.yaml -type f | sort)
}

prompt_application_choice() {
    local app_rows=() app_values=() app_labels=()
    local row value label default_index idx

    mapfile -t app_rows < <(list_applications)
    if [[ ${#app_rows[@]} -eq 0 ]]; then
        APPLICATION_DIR="$(prompt_default "MMCU_APPLICATION_DIR" "${APPLICATION_DIR:-applications/main}")"
        return
    fi

    for row in "${app_rows[@]}"; do
        IFS=$'\t' read -r value label <<< "$row"
        [[ -z "$value" || -z "$label" ]] && continue
        app_values+=("$value")
        app_labels+=("$label")
    done

    default_index=1
    if [[ -n "$APPLICATION_DIR" ]]; then
        for i in "${!app_values[@]}"; do
            [[ "${app_values[$i]}" == "$APPLICATION_DIR" ]] && default_index=$((i + 1))
        done
    else
        for i in "${!app_values[@]}"; do
            [[ "${app_values[$i]}" == "applications/main" ]] && default_index=$((i + 1))
        done
    fi

    idx="$(prompt_choice "Select MMCU_APPLICATION_DIR:" "$default_index" "${app_labels[@]}")"
    APPLICATION_DIR="${app_values[$((idx - 1))]}"
}

default_board_for_target() {
    case "$1" in
        rp2040)
            echo "pico"
            ;;
        rp2350)
            echo "pico2"
            ;;
        *)
            echo ""
            ;;
    esac
}

list_compatible_boards() {
    local platform="$1" target="$2" repo_root python_bin
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ -x "$repo_root/venv/bin/python" ]]; then
        python_bin="$repo_root/venv/bin/python"
    elif command -v python3 >/dev/null 2>&1; then
        python_bin="$(command -v python3)"
    else
        return 0
    fi

    "$python_bin" - "$repo_root" "$platform" "$target" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:
    raise SystemExit(0)

root = Path(sys.argv[1])
platform = sys.argv[2]
target = sys.argv[3]
target_chips = {
    "rp2040": "rp2040",
    "rp2350": "rp2350",
}
platform_targets = {
    "native": {"emu"},
    "mcu": {"emu", "cortex-m0", "cortex-m0plus"},
    "cmsis": {"cortex-m0", "cortex-m0plus", "rp2040"},
    "pico_sdk": {"rp2040", "rp2350"},
}
platform_chips = {
    item
    for item in platform_targets.get(platform, set())
    if item in target_chips
}
chip = target_chips.get(target, target)

registry_path = root / "boards" / "mmcu-boards.yaml"
if not registry_path.exists():
    raise SystemExit(0)

with registry_path.open("r", encoding="utf-8") as handle:
    registry = yaml.safe_load(handle) or {}

for collection_ref in registry.get("collections") or []:
    collection_path = root / "boards" / str(collection_ref.get("path", ""))
    if not collection_path.exists():
        continue
    with collection_path.open("r", encoding="utf-8") as handle:
        collection = yaml.safe_load(handle) or {}
    for board_ref in collection.get("boards") or []:
        name = str(board_ref.get("name", ""))
        board_path = collection_path.parent / str(board_ref.get("path", ""))
        if not name or not board_path.exists():
            continue
        with board_path.open("r", encoding="utf-8") as handle:
            board = yaml.safe_load(handle) or {}
        if platform not in (board.get("platforms") or []):
            continue
        target_label = ""
        if board.get("virtual"):
            compatible_targets = board.get("compatible_targets") or []
            if chip not in compatible_targets:
                continue
            if platform_chips and not set(compatible_targets).issubset(platform_chips):
                continue
            target_label = "/".join(compatible_targets) + ", virtual"
        else:
            board_target = str(board.get("target", ""))
            if board_target != chip:
                continue
            target_label = board_target
        print(f"{name}\t{name} - {target_label}")
PY
}

prompt_board_choice() {
    local default_board blank_label default_index idx row name label
    local board_values=() board_labels=() board_rows=()

    default_board="$(default_board_for_target "$TARGET")"
    if [[ -n "$default_board" ]]; then
        blank_label="blank - derive target default ($default_board)"
    else
        blank_label="blank - no board"
    fi

    mapfile -t board_rows < <(list_compatible_boards "$PLATFORM" "$TARGET")
    if [[ ${#board_rows[@]} -eq 0 ]]; then
        if [[ -n "$default_board" ]]; then
            BOARD="$(prompt_default "MMCU_BOARD override (blank = derive from target)" "$BOARD")"
        else
            BOARD="$(prompt_default "MMCU_BOARD override (blank = no board)" "$BOARD")"
        fi
        return
    fi

    board_values=("")
    board_labels=("$blank_label")
    for row in "${board_rows[@]}"; do
        IFS=$'\t' read -r name label <<< "$row"
        [[ -z "$name" || -z "$label" ]] && continue
        board_values+=("$name")
        board_labels+=("$label")
    done

    default_index=1
    if [[ -n "$BOARD" ]]; then
        for i in "${!board_values[@]}"; do
            [[ "${board_values[$i]}" == "$BOARD" ]] && default_index=$((i + 1))
        done
    fi

    idx="$(prompt_choice "Select MMCU_BOARD:" "$default_index" "${board_labels[@]}")"
    BOARD="${board_values[$((idx - 1))]}"
}

version_at_least() {
    local required="$1" actual="$2"
    [[ -n "$actual" ]] || return 1
    [[ "$(printf '%s\n' "$required" "$actual" | sort -V | head -n1)" == "$required" ]]
}

compiler_version_for() {
    local path="$1" version_line
    [[ -x "$path" ]] || return 0
    version_line="$("$path" --version 2>/dev/null | head -1)"
    if [[ "$version_line" == *clang* || "$version_line" == *Clang* ]]; then
        printf '%s\n' "$version_line" | sed -E 's/.*version ([0-9]+([.][0-9]+)*).*/\1/'
    else
        "$path" -dumpfullversion -dumpversion 2>/dev/null | head -1
    fi
}

native_c_candidate_for() {
    local cxx_path="$1" c_path

    if [[ -n "$MMCU_CC" ]]; then
        echo "$MMCU_CC"
        return 0
    fi
    if [[ -n "${CC:-}" ]]; then
        echo "$CC"
        return 0
    fi

    case "$(basename "$cxx_path")" in
        g++-*)
            c_path="$(dirname "$cxx_path")/gcc-${cxx_path##*g++-}"
            ;;
        clang++-*)
            c_path="$(dirname "$cxx_path")/clang-${cxx_path##*clang++-}"
            ;;
        g++)
            c_path="$(dirname "$cxx_path")/gcc"
            ;;
        clang++)
            c_path="$(dirname "$cxx_path")/clang"
            ;;
        c++)
            c_path=""
            ;;
        *)
            c_path=""
            ;;
    esac

    if [[ -n "$c_path" && -x "$c_path" ]]; then
        echo "$c_path"
    elif command -v cc >/dev/null 2>&1; then
        command -v cc
    elif command -v gcc >/dev/null 2>&1; then
        command -v gcc
    elif command -v clang >/dev/null 2>&1; then
        command -v clang
    fi
}

emit_native_toolchain_candidate() {
    local id="$1" family="$2" cxx_path="$3" cc_path version status reason label
    [[ -n "$cxx_path" && -x "$cxx_path" ]] || return 0
    cc_path="$(native_c_candidate_for "$cxx_path")"
    version="$(compiler_version_for "$cxx_path")"
    status="usable"
    reason=""
    if [[ "$family" == "gcc" ]] && ! version_at_least "15.0.0" "$version"; then
        status="unsupported"
        reason="need GCC 15+ for CMake C++20 module scanning"
    elif [[ "$family" == "clang" ]] && ! version_at_least "20.0.0" "$version"; then
        status="unsupported"
        reason="need Clang 20+ for CMake C++20 module scanning"
    fi
    if [[ "$status" == "usable" ]]; then
        label="$id - $cxx_path $version, usable for native C++20 modules"
    else
        label="$id - $cxx_path $version, unsupported: $reason"
    fi
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$id" "$family" "$cc_path" "$cxx_path" "$version" "$status" "$reason" "$label"
}

emit_arm_gcc_toolchain_candidate() {
    local cc_path cxx_path status reason label version
    cc_path="${ARM_GCC:-}"
    cxx_path="${ARM_GXX:-}"
    [[ -z "$cc_path" ]] && command -v arm-none-eabi-gcc >/dev/null 2>&1 && cc_path="$(command -v arm-none-eabi-gcc)"
    [[ -z "$cxx_path" ]] && command -v arm-none-eabi-g++ >/dev/null 2>&1 && cxx_path="$(command -v arm-none-eabi-g++)"
    status="usable"
    reason=""
    if [[ -z "$cc_path" || -z "$cxx_path" ]]; then
        status="unsupported"
        reason="arm-none-eabi-gcc/g++ not found"
    fi
    version="$(compiler_version_for "${cxx_path:-$cc_path}")"
    if [[ "$status" == "usable" ]]; then
        label="arm-none-eabi-gcc - $cxx_path ${version:-unknown}, usable"
    else
        label="arm-none-eabi-gcc - unsupported: $reason"
    fi
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "arm-none-eabi-gcc" "gcc" "$cc_path" "$cxx_path" "$version" "$status" "$reason" "$label"
}

emit_arm_clang_toolchain_candidate() {
    local platform="$1" target="$2" cc_path cxx_path major version status reason label
    for major in 23 22 21 20; do
        if command -v "clang++-$major" >/dev/null 2>&1; then
            cxx_path="$(command -v "clang++-$major")"
            command -v "clang-$major" >/dev/null 2>&1 && cc_path="$(command -v "clang-$major")"
            break
        fi
    done
    if [[ -z "${cxx_path:-}" && -n "$CLANG_CXX" ]]; then
        cxx_path="$CLANG_CXX"
        cc_path="$CLANG_CC"
    fi
    if [[ -z "${cxx_path:-}" ]] && command -v clang++ >/dev/null 2>&1; then
        cxx_path="$(command -v clang++)"
        command -v clang >/dev/null 2>&1 && cc_path="$(command -v clang)"
    fi
    version="$(compiler_version_for "${cxx_path:-}")"
    status="usable"
    reason=""
    if [[ -z "${cc_path:-}" || -z "${cxx_path:-}" ]]; then
        status="unsupported"
        reason="clang/clang++ 20+ not found"
    elif ! version_at_least "20.0.0" "$version"; then
        status="unsupported"
        reason="need Clang 20+"
    elif [[ "$platform" == "pico_sdk" && ( "$target" == "rp2040" || "$target" == "rp2350" ) ]]; then
        status="unsupported"
        reason="pico-sdk Clang runtime/sysroot integration is not wired yet"
    fi
    if [[ "$status" == "usable" ]]; then
        label="clang-arm-none-eabi - $cxx_path $version, usable"
    else
        label="clang-arm-none-eabi - ${cxx_path:-not found} ${version:-}, unsupported: $reason"
    fi
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "clang-arm-none-eabi" "clang" "${cc_path:-}" "${cxx_path:-}" "$version" "$status" "$reason" "$label"
}

list_toolchain_candidates() {
    local platform="$1" target="$2" major candidate path seen_paths=""
    if [[ "$platform" == "native" ]]; then
        if [[ -n "$MMCU_CXX" ]]; then
            case "$(basename "$MMCU_CXX")" in
                *clang++*) emit_native_toolchain_candidate "clang-explicit" "clang" "$MMCU_CXX" ;;
                *) emit_native_toolchain_candidate "gcc-explicit" "gcc" "$MMCU_CXX" ;;
            esac
            return 0
        fi
        if [[ -n "${CXX:-}" ]]; then
            case "$(basename "$CXX")" in
                *clang++*) emit_native_toolchain_candidate "clang-env" "clang" "$CXX" ;;
                *) emit_native_toolchain_candidate "gcc-env" "gcc" "$CXX" ;;
            esac
            return 0
        fi
        for major in 23 22 21 20 19 18 17 16 15; do
            candidate="g++-$major"
            if command -v "$candidate" >/dev/null 2>&1; then
                path="$(command -v "$candidate")"
                [[ "$seen_paths" == *"|$path|"* ]] || emit_native_toolchain_candidate "gcc-$major" "gcc" "$path"
                seen_paths="$seen_paths|$path|"
            fi
        done
        for major in 23 22 21 20; do
            candidate="clang++-$major"
            if command -v "$candidate" >/dev/null 2>&1; then
                path="$(command -v "$candidate")"
                [[ "$seen_paths" == *"|$path|"* ]] || emit_native_toolchain_candidate "clang-$major" "clang" "$path"
                seen_paths="$seen_paths|$path|"
            fi
        done
        for candidate in c++ g++ clang++; do
            if command -v "$candidate" >/dev/null 2>&1; then
                path="$(command -v "$candidate")"
                [[ "$seen_paths" == *"|$path|"* ]] && continue
                case "$candidate" in
                    clang++) emit_native_toolchain_candidate "clang-system" "clang" "$path" ;;
                    *) emit_native_toolchain_candidate "gcc-system" "gcc" "$path" ;;
                esac
                seen_paths="$seen_paths|$path|"
            fi
        done
    else
        emit_arm_gcc_toolchain_candidate
        emit_arm_clang_toolchain_candidate "$platform" "$target"
    fi
}

prompt_toolchain_choice() {
    local rows=() usable_indexes=() labels=() default_index=1 idx row
    local id family cc_path cxx_path version status reason label
    local selected_id selected_family selected_cc_path selected_cxx_path

    mapfile -t rows < <(list_toolchain_candidates "$PLATFORM" "$TARGET")
    if [[ ${#rows[@]} -eq 0 ]]; then
        echo "Error: no compiler toolchains were discovered." >&2
        exit 1
    fi

    echo "Discovered compiler toolchains:"
    for i in "${!rows[@]}"; do
        IFS='|' read -r id family cc_path cxx_path version status reason label <<< "${rows[$i]}"
        labels+=("$label")
        if [[ "$status" == "usable" ]]; then
            usable_indexes+=("$i")
            if [[ ${#usable_indexes[@]} -eq 1 ]]; then
                default_index=$((i + 1))
            fi
        fi
    done

    if [[ ${#usable_indexes[@]} -eq 0 ]]; then
        for label in "${labels[@]}"; do
            echo "  - $label"
        done
        echo "Error: no compatible compiler toolchain was found for MMCU_PLATFORM=$PLATFORM MMCU_TARGET=$TARGET." >&2
        exit 1
    fi

    if [[ ${#usable_indexes[@]} -eq 1 && ${#rows[@]} -gt 1 ]]; then
        idx="${usable_indexes[0]}"
        IFS='|' read -r id family cc_path cxx_path version status reason label <<< "${rows[$idx]}"
        selected_id="$id"
        selected_family="$family"
        selected_cc_path="$cc_path"
        selected_cxx_path="$cxx_path"
        echo "Only one compatible compiler toolchain was found:"
        echo "  $label"
        echo
        echo "Rejected toolchains:"
        for i in "${!rows[@]}"; do
            [[ "$i" == "$idx" ]] && continue
            IFS='|' read -r id family cc_path cxx_path version status reason label <<< "${rows[$i]}"
            [[ "$status" == "usable" ]] || echo "  $label"
        done
        echo
        if ! prompt_yes_no "Use $selected_id?" "y"; then
            echo "Aborted." >&2
            exit 1
        fi
        id="$selected_id"
        family="$selected_family"
        cc_path="$selected_cc_path"
        cxx_path="$selected_cxx_path"
    else
        idx="$(prompt_choice "Select compiler toolchain:" "$default_index" "${labels[@]}")"
        idx=$((idx - 1))
        IFS='|' read -r id family cc_path cxx_path version status reason label <<< "${rows[$idx]}"
        if [[ "$status" != "usable" ]]; then
            echo "Error: selected toolchain is unsupported: $reason" >&2
            exit 1
        fi
    fi

    COMPILER="$family"
    if [[ "$PLATFORM" == "native" ]]; then
        MMCU_CC="$cc_path"
        MMCU_CXX="$cxx_path"
        TOOLCHAIN_FILE=""
    elif [[ "$family" == "gcc" ]]; then
        ARM_GCC="$cc_path"
        ARM_GXX="$cxx_path"
        TOOLCHAIN_FILE=""
    else
        CLANG_CC="$cc_path"
        CLANG_CXX="$cxx_path"
        TOOLCHAIN_FILE=""
    fi
}

run_interactive() {
    if [[ ! -t 0 ]]; then
        echo "Error: --interactive requires an interactive terminal (stdin is not a tty)." >&2
        exit 1
    fi

    echo "MMCU interactive configuration (docs/configure.md)"
    echo "===================================================="

    prompt_application_choice

    local platform_values=(native mcu cmsis pico_sdk)
    local platform_labels=(
        "native   - host build, emu target"
        "mcu      - generic bare-metal: emu, cortex-m0, cortex-m0plus"
        "cmsis    - CMSIS bare-metal ARM: cortex-m0, cortex-m0plus, rp2040"
        "pico_sdk - Raspberry Pi Pico SDK: rp2040, rp2350"
    )
    local platform_default=1
    case "$PLATFORM" in
        mcu) platform_default=2 ;;
        cmsis) platform_default=3 ;;
        pico_sdk) platform_default=4 ;;
    esac
    local idx
    idx="$(prompt_choice "Select MMCU_PLATFORM:" "$platform_default" "${platform_labels[@]}")"
    PLATFORM="${platform_values[$((idx - 1))]}"

    local target_values=() target_labels=()
    case "$PLATFORM" in
        native)
            target_values=(emu)
            target_labels=("emu - placeholder GPIO/UART target")
            ;;
        mcu)
            target_values=(emu cortex-m0 cortex-m0plus)
            target_labels=(
                "emu           - placeholder GPIO/UART target, no CMSIS required"
                "cortex-m0     - CMSIS-based Cortex-M0 target"
                "cortex-m0plus - CMSIS-based Cortex-M0+ target"
            )
            ;;
        cmsis)
            target_values=(cortex-m0 cortex-m0plus rp2040)
            target_labels=(
                "cortex-m0     - CMSIS-Core Cortex-M0 target"
                "cortex-m0plus - CMSIS-Core Cortex-M0+ target"
                "rp2040        - Raspberry Pi RP2040 via CMSIS-RP2xxx-DFP"
            )
            ;;
        pico_sdk)
            target_values=(rp2040 rp2350)
            target_labels=(
                "rp2040        - Cortex-M0+ (RP2040), real pico-sdk boot2/clocks, gcc only"
                "rp2350        - Cortex-M33 (RP2350), real pico-sdk boot2/clocks, gcc only"
            )
            ;;
    esac

    if [[ ${#target_values[@]} -eq 1 ]]; then
        TARGET="${target_values[0]}"
        echo "MMCU_TARGET: $TARGET (only option for $PLATFORM)"
    else
        local target_default=1
        for i in "${!target_values[@]}"; do
            [[ "${target_values[$i]}" == "$TARGET" ]] && target_default=$((i + 1))
        done
        idx="$(prompt_choice "Select MMCU_TARGET:" "$target_default" "${target_labels[@]}")"
        TARGET="${target_values[$((idx - 1))]}"
    fi

    local _rp2040_cmsis_dfp_backed=0
    if [[ "$PLATFORM" == "cmsis" && "$TARGET" == "rp2040" ]]; then
        _rp2040_cmsis_dfp_backed=1
    fi

    if [[ "$PLATFORM" == "mcu" || "$PLATFORM" == "cmsis" || "$PLATFORM" == "pico_sdk" ]]; then
        prompt_board_choice
        prompt_toolchain_choice

        CPU="$(prompt_default "ARM CPU for -mcpu (blank = derive from target)" "$CPU")"

        if [[ "$TARGET" != "emu" && "$PLATFORM" != "pico_sdk" ]]; then
            CMSIS_DIR="$(prompt_default "CMSIS_6 checkout path (blank = platforms/cmsis/CMSIS_6, then third_party/CMSIS_6 fallback)" "$CMSIS_DIR")"
        fi
        if [[ $_rp2040_cmsis_dfp_backed -eq 1 ]]; then
            CMSIS_RP2XXX_DFP_DIR="$(prompt_default "CMSIS-RP2xxx-DFP checkout path (blank = platforms/cmsis/CMSIS-RP2xxx-DFP)" "$CMSIS_RP2XXX_DFP_DIR")"
        fi

        if prompt_yes_no "Enable linker map + cross-reference (MMCU_LINKER_MAP)?" "n"; then
            LINKER_MAP=1
        else
            LINKER_MAP=0
        fi
    else
        prompt_toolchain_choice
    fi

    local type_values=(Release Debug RelWithDebInfo MinSizeRel)
    local type_labels=("Release" "Debug" "RelWithDebInfo" "MinSizeRel")
    local type_default=1
    for i in "${!type_values[@]}"; do
        [[ "${type_values[$i]}" == "$BUILD_TYPE" ]] && type_default=$((i + 1))
    done
    idx="$(prompt_choice "Select CMAKE_BUILD_TYPE:" "$type_default" "${type_labels[@]}")"
    BUILD_TYPE="${type_values[$((idx - 1))]}"

    local default_build_dir
    if [[ "$PLATFORM" == "native" ]]; then
        default_build_dir="build"
    elif [[ "$PLATFORM" == "cmsis" ]]; then
        default_build_dir="build-cmsis-${TARGET}-${COMPILER}"
    else
        default_build_dir="build-${TARGET}-${COMPILER}"
    fi
    BUILD_DIR="$(prompt_default "Build directory" "${BUILD_DIR:-$default_build_dir}")"

    if prompt_yes_no "Remove existing build directory first (--clean)?" "n"; then
        CLEAN=1
    else
        CLEAN=0
    fi

    echo
    echo "Summary:"
    [[ -n "$APPLICATION_DIR" ]] && echo "  MMCU_APPLICATION_DIR = $APPLICATION_DIR"
    echo "  MMCU_PLATFORM = $PLATFORM"
    echo "  MMCU_TARGET   = $TARGET"
    [[ -n "$BOARD" ]] && echo "  MMCU_BOARD    = $BOARD"
    echo "  compiler      = $COMPILER"
    [[ -n "$MMCU_CC" ]] && echo "  MMCU_CC       = $MMCU_CC"
    [[ -n "$MMCU_CXX" ]] && echo "  MMCU_CXX      = $MMCU_CXX"
    [[ -n "$ARM_GCC" ]] && echo "  MMCU_ARM_GCC  = $ARM_GCC"
    [[ -n "$ARM_GXX" ]] && echo "  MMCU_ARM_GXX  = $ARM_GXX"
    [[ -n "$CLANG_CC" ]] && echo "  MMCU_CLANG_CC = $CLANG_CC"
    [[ -n "$CLANG_CXX" ]] && echo "  MMCU_CLANG_CXX = $CLANG_CXX"
    [[ -n "$CPU" ]] && echo "  MMCU_CPU      = $CPU"
    [[ -n "$CMSIS_DIR" ]] && echo "  MMCU_CMSIS_DIR = $CMSIS_DIR"
    [[ -n "$CMSIS_RP2XXX_DFP_DIR" ]] && echo "  MMCU_CMSIS_RP2XXX_DFP_DIR = $CMSIS_RP2XXX_DFP_DIR"
    [[ $LINKER_MAP -eq 1 ]] && echo "  MMCU_LINKER_MAP = ON"
    echo "  build type    = $BUILD_TYPE"
    echo "  build dir     = $BUILD_DIR"
    [[ $CLEAN -eq 1 ]] && echo "  clean         = yes"
    echo
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--platform)
            PLATFORM="${2:-}"
            shift 2
            ;;
        -t|--target)
            TARGET="${2:-}"
            shift 2
            ;;
        --board)
            BOARD="${2:-}"
            shift 2
            ;;
        --compiler)
            COMPILER="${2:-}"
            shift 2
            ;;
        --toolchain-file)
            TOOLCHAIN_FILE="${2:-}"
            shift 2
            ;;
        --cpu)
            CPU="${2:-}"
            shift 2
            ;;
        --cmsis-dir)
            CMSIS_DIR="${2:-}"
            shift 2
            ;;
        --cmsis-git-tag)
            CMSIS_GIT_TAG="${2:-}"
            shift 2
            ;;
        --cmsis-rp2xxx-dfp-dir)
            CMSIS_RP2XXX_DFP_DIR="${2:-}"
            shift 2
            ;;
        --linker-map)
            LINKER_MAP=1
            shift
            ;;
        --arm-gcc)
            ARM_GCC="${2:-}"
            shift 2
            ;;
        --arm-gxx)
            ARM_GXX="${2:-}"
            shift 2
            ;;
        --clang-cc)
            CLANG_CC="${2:-}"
            shift 2
            ;;
        --clang-cxx)
            CLANG_CXX="${2:-}"
            shift 2
            ;;
        --cc)
            MMCU_CC="${2:-}"
            shift 2
            ;;
        --cxx)
            MMCU_CXX="${2:-}"
            shift 2
            ;;
        --application-dir|--app-dir)
            APPLICATION_DIR="${2:-}"
            shift 2
            ;;
        -d|--build-dir)
            BUILD_DIR="${2:-}"
            shift 2
            ;;
        -b|--type)
            BUILD_TYPE="${2:-}"
            shift 2
            ;;
        -G|--generator)
            GENERATOR="${2:-}"
            shift 2
            ;;
        -c|--clean)
            CLEAN=1
            shift
            ;;
        -i|--interactive)
            INTERACTIVE=1
            shift
            ;;
        --list-toolchains)
            LIST_TOOLCHAINS=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
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

if [[ $INTERACTIVE -eq 1 ]]; then
    run_interactive
fi

case "$PLATFORM" in
    native|mcu|cmsis|pico_sdk)
        ;;
    *)
        echo "Error: --platform must be one of: native, mcu, cmsis, pico_sdk" >&2
        exit 1
        ;;
esac

if [[ $LIST_TOOLCHAINS -eq 1 ]]; then
    case "$PLATFORM" in
        native) TARGET="${TARGET:-emu}" ;;
        mcu) TARGET="${TARGET:-emu}" ;;
        cmsis) TARGET="${TARGET:-cortex-m0}" ;;
        pico_sdk) TARGET="${TARGET:-rp2040}" ;;
    esac
    list_toolchain_candidates "$PLATFORM" "$TARGET"
    exit 0
fi

if [[ "$PLATFORM" == "native" ]]; then
    if [[ -n "$TOOLCHAIN_FILE" ]]; then
        echo "Error: --toolchain-file only applies to --platform mcu, cmsis, or pico_sdk" >&2
        exit 1
    fi
fi

if [[ "$PLATFORM" == "pico_sdk" ]]; then
    _mmcu_effective_target="${TARGET:-rp2040}"
    if [[ ( "$_mmcu_effective_target" == "rp2040" || "$_mmcu_effective_target" == "rp2350" ) \
          && "$COMPILER" == "clang" && -z "$TOOLCHAIN_FILE" ]]; then
        echo "Error: MMCU_TARGET=$_mmcu_effective_target only supports --compiler gcc for now;" >&2
        echo "       pico-sdk clang support requires a configured ARM clang runtime/sysroot and is not wired yet." >&2
        exit 1
    fi
fi

if [[ "$PLATFORM" == "cmsis" ]]; then
    _mmcu_effective_target="${TARGET:-cortex-m0}"
fi

if [[ ( "$PLATFORM" == "mcu" || "$PLATFORM" == "cmsis" || "$PLATFORM" == "pico_sdk" ) && -z "$TOOLCHAIN_FILE" ]]; then
    case "$COMPILER" in
        gcc)
            TOOLCHAIN_FILE="cmake/toolchains/arm-none-eabi-gcc.cmake"
            ;;
        clang)
            TOOLCHAIN_FILE="cmake/toolchains/arm-none-eabi-clang.cmake"
            ;;
        *)
            echo "Error: --compiler must be one of: gcc, clang" >&2
            exit 1
            ;;
    esac
fi

if ! command -v cmake >/dev/null 2>&1; then
    echo "Error: cmake not found in PATH." >&2
    exit 1
fi

CMAKE_VERSION="$(cmake --version | awk 'NR==1 {print $3}')"
if [[ "$(printf '%s\n' "4.0.0" "$CMAKE_VERSION" | sort -V | head -n1)" != "4.0.0" ]]; then
    echo "Error: CMake 4.0+ is required. Found: $CMAKE_VERSION" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

read_config_var() {
    local var="$1"
    [[ -f .config ]] || return 0
    grep "^${var}=" .config 2>/dev/null | tail -1 | cut -d= -f2-
}

if [[ -z "$APPLICATION_DIR" ]]; then
    APPLICATION_DIR="$(read_config_var MMCU_APPLICATION_DIR)"
fi

if [[ "$PLATFORM" == "pico_sdk" \
      && ( "$_mmcu_effective_target" == "rp2040" || "$_mmcu_effective_target" == "rp2350" ) \
      && ! -e "platforms/pico-sdk/pico-sdk/pico_sdk_init.cmake" ]]; then
    if [[ $INTERACTIVE -eq 1 ]]; then
        echo "pico-sdk is not installed yet at platforms/pico-sdk/pico-sdk (needed for MMCU_TARGET=$_mmcu_effective_target)."
        if prompt_yes_no "Run ./platforms/pico-sdk/pico-sdk-install.sh now? (clones pico-sdk + builds picotool; can take a few minutes)" "y"; then
            "$SCRIPT_DIR/platforms/pico-sdk/pico-sdk-install.sh"
        else
            echo "Aborted. Run ./platforms/pico-sdk/pico-sdk-install.sh first." >&2
            exit 1
        fi
    else
        echo "Error: MMCU_TARGET=$_mmcu_effective_target requires a vendored pico-sdk checkout at platforms/pico-sdk/pico-sdk." >&2
        echo "       Run ./platforms/pico-sdk/pico-sdk-install.sh first." >&2
        exit 1
    fi
fi

if [[ "$PLATFORM" == "cmsis" && "${_mmcu_effective_target:-${TARGET:-cortex-m0}}" == "rp2040" ]]; then
    _mmcu_dfp_probe="${CMSIS_RP2XXX_DFP_DIR:-platforms/cmsis/CMSIS-RP2xxx-DFP}"
    if [[ "$_mmcu_dfp_probe" != /* ]]; then
        _mmcu_dfp_probe="$SCRIPT_DIR/$_mmcu_dfp_probe"
    fi
    if [[ ! -e "$_mmcu_dfp_probe/CMSIS/Device/RP2040/Include/rp2040.h" ]]; then
        if [[ $INTERACTIVE -eq 1 ]]; then
            echo "CMSIS-RP2xxx-DFP is not installed yet at $_mmcu_dfp_probe (needed for MMCU_PLATFORM=cmsis MMCU_TARGET=rp2040)."
            if prompt_yes_no "Run ./platforms/cmsis/cmsis-install.sh now? (clones CMSIS_6 + CMSIS-RP2xxx-DFP)" "y"; then
                "$SCRIPT_DIR/platforms/cmsis/cmsis-install.sh"
            else
                echo "Aborted. Run ./platforms/cmsis/cmsis-install.sh first." >&2
                exit 1
            fi
        else
            echo "Error: MMCU_PLATFORM=cmsis MMCU_TARGET=rp2040 requires Raspberry Pi CMSIS-RP2xxx-DFP at $_mmcu_dfp_probe." >&2
            echo "       Run ./platforms/cmsis/cmsis-install.sh, or pass --cmsis-rp2xxx-dfp-dir <checkout>." >&2
            exit 1
        fi
    fi
fi

if [[ -z "$BUILD_DIR" ]]; then
    if [[ "$PLATFORM" == "native" ]]; then
        BUILD_DIR="build"
    elif [[ "$PLATFORM" == "mcu" ]]; then
        BUILD_DIR="build-${TARGET:-emu}-${COMPILER}"
    elif [[ "$PLATFORM" == "cmsis" ]]; then
        BUILD_DIR="build-cmsis-${TARGET:-cortex-m0}-${COMPILER}"
    else
        BUILD_DIR="build-${TARGET:-rp2040}-${COMPILER}"
    fi
fi

if [[ $CLEAN -eq 1 ]]; then
    rm -rf "$BUILD_DIR"
fi

check_ninja_version() {
    local ninja_path version
    if ! command -v ninja >/dev/null 2>&1; then
        echo "Error: Ninja 1.11+ is required for MMCU C++20 module builds, but ninja was not found." >&2
        echo "       Install or select a CMake generator with C++20 module support." >&2
        exit 1
    fi
    ninja_path="$(command -v ninja)"
    version="$("$ninja_path" --version 2>/dev/null | head -1)"
    if [[ "$(printf '%s\n' "1.11.0" "$version" | sort -V | head -n1)" != "1.11.0" ]]; then
        echo "Error: Ninja 1.11+ is required for CMake C++20 module support. Found: $version" >&2
        echo "       Your CMake error is caused by Ninja being too old for C++20 modules." >&2
        exit 1
    fi
    NINJA_PROGRAM="$ninja_path"
}

native_cxx_candidate() {
    local candidate major
    if [[ -n "$MMCU_CXX" ]]; then
        echo "$MMCU_CXX"
        return 0
    elif [[ -n "${CXX:-}" ]]; then
        echo "$CXX"
        return 0
    fi
    if [[ "$COMPILER" == "clang" ]]; then
        for major in 23 22 21 20; do
            candidate="clang++-$major"
            command -v "$candidate" >/dev/null 2>&1 && command -v "$candidate" && return 0
        done
        command -v clang++ >/dev/null 2>&1 && command -v clang++ && return 0
    fi
    for major in 23 22 21 20 19 18 17 16 15; do
        candidate="g++-$major"
        command -v "$candidate" >/dev/null 2>&1 && command -v "$candidate" && return 0
    done
    for major in 23 22 21 20; do
        candidate="clang++-$major"
        command -v "$candidate" >/dev/null 2>&1 && command -v "$candidate" && return 0
    done
    for candidate in c++ g++ clang++; do
        command -v "$candidate" >/dev/null 2>&1 && command -v "$candidate" && return 0
    done
}

check_native_cxx_modules_compiler() {
    local cxx_path version_line version compiler_id

    [[ "$PLATFORM" == "native" ]] || return 0

    cxx_path="$(native_cxx_candidate)"
    if [[ -z "$cxx_path" ]]; then
        echo "Error: native builds require a C++ compiler with C++20 module dependency scanning." >&2
        echo "       Install GCC 15+ or Clang 20+, then rerun ./configure.sh." >&2
        echo "       On Debian/Ubuntu, './setup.sh --install-clang' can install a suitable Clang." >&2
        exit 1
    fi

    version_line="$("$cxx_path" --version 2>/dev/null | head -1)"
    if [[ "$version_line" == *clang* || "$version_line" == *Clang* ]]; then
        compiler_id="Clang"
        version="$(printf '%s\n' "$version_line" | sed -E 's/.*version ([0-9]+([.][0-9]+)*).*/\1/')"
        if version_at_least "20.0.0" "$version"; then
            NATIVE_CXX_PROGRAM="$cxx_path"
            NATIVE_C_PROGRAM="$(native_c_candidate_for "$cxx_path")"
            COMPILER="clang"
            echo "Using native C++20 module compiler: $NATIVE_CXX_PROGRAM"
            [[ -n "$NATIVE_C_PROGRAM" ]] && echo "Using native C compiler: $NATIVE_C_PROGRAM"
            return 0
        fi
        echo "Error: native C++20 module builds require Clang 20+ or GCC 15+." >&2
        echo "       Found $compiler_id $version at $cxx_path." >&2
        echo "       Select a newer compiler, for example:" >&2
        echo "         CC=/usr/bin/gcc-15 CXX=/usr/bin/g++-15 ./configure.sh --clean" >&2
        echo "         CC=/usr/bin/clang-20 CXX=/usr/bin/clang++-20 ./configure.sh --clean" >&2
        echo "       On Debian/Ubuntu, './setup.sh --install-clang' can install a suitable Clang." >&2
        exit 1
    fi

    version="$("$cxx_path" -dumpfullversion -dumpversion 2>/dev/null | head -1)"
    if version_at_least "15.0.0" "$version"; then
        NATIVE_CXX_PROGRAM="$cxx_path"
        NATIVE_C_PROGRAM="$(native_c_candidate_for "$cxx_path")"
        COMPILER="gcc"
        echo "Using native C++20 module compiler: $NATIVE_CXX_PROGRAM"
        [[ -n "$NATIVE_C_PROGRAM" ]] && echo "Using native C compiler: $NATIVE_C_PROGRAM"
        return 0
    fi

    version="$("$cxx_path" -dumpfullversion -dumpversion 2>/dev/null | head -1)"
    echo "Error: native C++20 module builds require GCC 15+ or Clang 20+." >&2
    echo "       Found GNU $version at $cxx_path." >&2
    echo "       CMake cannot discover C++20 module import dependencies with this compiler." >&2
    echo "       Select a newer compiler, for example:" >&2
    echo "         CC=/usr/bin/gcc-15 CXX=/usr/bin/g++-15 ./configure.sh --clean" >&2
    echo "         CC=/usr/bin/clang-20 CXX=/usr/bin/clang++-20 ./configure.sh --clean" >&2
    echo "       On Debian/Ubuntu, './setup.sh --install-clang' can install a suitable Clang." >&2
    exit 1
}

cached_cmake_var() {
    local var="$1"
    [[ -f "$BUILD_DIR/CMakeCache.txt" ]] || return 0
    grep "^${var}:" "$BUILD_DIR/CMakeCache.txt" 2>/dev/null | head -1 | cut -d= -f2-
}

check_cached_ninja_version() {
    local cached_program version
    cached_program="$(cached_cmake_var CMAKE_MAKE_PROGRAM)"
    [[ -n "$cached_program" ]] || return 0

    if [[ ! -x "$cached_program" ]]; then
        echo "Error: $BUILD_DIR is already configured with CMAKE_MAKE_PROGRAM=$cached_program, but that file is not executable." >&2
        echo "       Use './configure.sh --clean' or a fresh --build-dir so CMake can select $NINJA_PROGRAM." >&2
        exit 1
    fi

    version="$("$cached_program" --version 2>/dev/null | head -1)"
    if [[ "$(printf '%s\n' "1.11.0" "$version" | sort -V | head -n1)" != "1.11.0" ]]; then
        echo "Error: $BUILD_DIR is already configured with CMAKE_MAKE_PROGRAM=$cached_program (Ninja $version)." >&2
        echo "       MMCU requires Ninja 1.11+ for C++20 modules; your current PATH ninja is $NINJA_PROGRAM." >&2
        echo "       Use './configure.sh --clean' or a fresh --build-dir so CMake can select the newer Ninja." >&2
        exit 1
    fi
}

if [[ -z "$GENERATOR" ]] && command -v ninja >/dev/null 2>&1; then
    GENERATOR="Ninja"
fi
case "$GENERATOR" in
    ""|"Ninja"|"Ninja Multi-Config")
        check_ninja_version
        check_cached_ninja_version
        check_native_cxx_modules_compiler
        ;;
    "Visual Studio "*)
        ;;
    *)
        echo "Error: generator '$GENERATOR' is not supported for MMCU C++20 module builds." >&2
        echo "       Use Ninja 1.11+ or Ninja Multi-Config." >&2
        exit 1
        ;;
esac

compiler_kind_from_build_dir() {
    local file line compiler_path
    for file in "$BUILD_DIR"/CMakeFiles/*/CMakeCXXCompiler.cmake; do
        [[ -f "$file" ]] || continue
        line="$(grep '^set(CMAKE_CXX_COMPILER ' "$file" 2>/dev/null | head -1 || true)"
        compiler_path="${line#*\"}"
        compiler_path="${compiler_path%%\"*}"
        case "$compiler_path" in
            *clang++*|*clang*) echo "clang"; return 0 ;;
            *g++*|*gcc*|*c++*) echo "gcc"; return 0 ;;
        esac
    done
    return 0
}

desired_compiler_kind="$COMPILER"
case "$TOOLCHAIN_FILE" in
    *clang*) desired_compiler_kind="clang" ;;
    *gcc*) desired_compiler_kind="gcc" ;;
esac
if [[ -f "$BUILD_DIR/CMakeCache.txt" && "$PLATFORM" != "native" ]]; then
    existing_compiler_kind="$(compiler_kind_from_build_dir)"
    if [[ -n "$existing_compiler_kind" && -n "$desired_compiler_kind" && "$existing_compiler_kind" != "$desired_compiler_kind" ]]; then
        echo "Error: $BUILD_DIR is already configured with compiler=$existing_compiler_kind, but this configure requests compiler=$desired_compiler_kind." >&2
        echo "       CMake cannot switch toolchains in an existing build directory." >&2
        echo "       Use a fresh --build-dir, or rerun configure with --clean if you want this directory recreated." >&2
        exit 1
    fi
fi

CMAKE_ARGS=(
    -S .
    -B "$BUILD_DIR"
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
    -DMMCU_PLATFORM="$PLATFORM"
)
if [[ $VERBOSE -eq 1 ]]; then
    CMAKE_ARGS=(--log-level=VERBOSE "${CMAKE_ARGS[@]}")
fi
if [[ -n "$TARGET" ]]; then
    CMAKE_ARGS+=(-DMMCU_TARGET="$TARGET")
fi
if [[ -n "$BOARD" ]]; then
    CMAKE_ARGS+=(-DMMCU_BOARD="$BOARD")
fi
if [[ -n "$TOOLCHAIN_FILE" ]]; then
    CMAKE_ARGS+=(-DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE")
fi
if [[ "$PLATFORM" == "native" && -n "${NATIVE_CXX_PROGRAM:-}" ]]; then
    CMAKE_ARGS+=(-DCMAKE_CXX_COMPILER="$NATIVE_CXX_PROGRAM")
fi
if [[ "$PLATFORM" == "native" && -n "${NATIVE_C_PROGRAM:-}" ]]; then
    CMAKE_ARGS+=(-DCMAKE_C_COMPILER="$NATIVE_C_PROGRAM")
fi
if [[ -n "$CPU" ]]; then
    CMAKE_ARGS+=(-DMMCU_CPU="$CPU")
fi
if [[ -n "$CMSIS_DIR" ]]; then
    CMAKE_ARGS+=(-DMMCU_CMSIS_DIR="$CMSIS_DIR")
fi
CMAKE_ARGS+=(-DMMCU_CMSIS_GIT_TAG="$CMSIS_GIT_TAG")
if [[ -n "$CMSIS_RP2XXX_DFP_DIR" ]]; then
    CMAKE_ARGS+=(-DMMCU_CMSIS_RP2XXX_DFP_DIR="$CMSIS_RP2XXX_DFP_DIR")
fi
if [[ $LINKER_MAP -eq 1 ]]; then
    CMAKE_ARGS+=(-DMMCU_LINKER_MAP=ON)
fi
if [[ -n "$ARM_GCC" ]]; then
    CMAKE_ARGS+=(-DMMCU_ARM_GCC="$ARM_GCC")
fi
if [[ -n "$ARM_GXX" ]]; then
    CMAKE_ARGS+=(-DMMCU_ARM_GXX="$ARM_GXX")
fi
if [[ -n "$CLANG_CC" ]]; then
    CMAKE_ARGS+=(-DMMCU_CLANG_CC="$CLANG_CC")
fi
if [[ -n "$CLANG_CXX" ]]; then
    CMAKE_ARGS+=(-DMMCU_CLANG_CXX="$CLANG_CXX")
fi
if [[ -n "$APPLICATION_DIR" ]]; then
    CMAKE_ARGS+=(-DMMCU_APPLICATION_DIR="$APPLICATION_DIR")
fi
if [[ -n "$GENERATOR" ]]; then
    CMAKE_ARGS+=(-G "$GENERATOR")
fi
if [[ -n "${NINJA_PROGRAM:-}" && ( "$GENERATOR" == "Ninja" || "$GENERATOR" == "Ninja Multi-Config" ) ]]; then
    CMAKE_ARGS+=(-DCMAKE_MAKE_PROGRAM="$NINJA_PROGRAM")
fi

echo "==> Configuring MMCU_PLATFORM=$PLATFORM${TARGET:+ MMCU_TARGET=$TARGET}${APPLICATION_DIR:+ MMCU_APPLICATION_DIR=$APPLICATION_DIR} in $BUILD_DIR"
cmake "${CMAKE_ARGS[@]}"

cat > .config <<CONFIG
# Written by ./configure.sh. Read by build.sh/run.sh as the default
# --build-dir when none is given, and by platform.sh install as the default
# --platform when none is given, so scripts act on what was last configured
# instead of always defaulting to plain native/build. Not consulted by
# clean.sh, which discovers every configured build dir on its own. Safe to
# delete.
MMCU_BUILD_DIR=$BUILD_DIR
MMCU_PLATFORM=$PLATFORM
MMCU_TARGET=$TARGET
MMCU_BOARD=$BOARD
CMAKE_BUILD_TYPE=$BUILD_TYPE
MMCU_COMPILER=$COMPILER
CMAKE_TOOLCHAIN_FILE=$TOOLCHAIN_FILE
MMCU_CPU=$CPU
MMCU_CMSIS_DIR=$CMSIS_DIR
MMCU_CMSIS_GIT_TAG=$CMSIS_GIT_TAG
MMCU_CMSIS_RP2XXX_DFP_DIR=$CMSIS_RP2XXX_DFP_DIR
MMCU_LINKER_MAP=$LINKER_MAP
MMCU_CC=${NATIVE_C_PROGRAM:-$MMCU_CC}
MMCU_CXX=${NATIVE_CXX_PROGRAM:-$MMCU_CXX}
MMCU_ARM_GCC=$ARM_GCC
MMCU_ARM_GXX=$ARM_GXX
MMCU_CLANG_CC=$CLANG_CC
MMCU_CLANG_CXX=$CLANG_CXX
MMCU_APPLICATION_DIR=$APPLICATION_DIR
CONFIG

echo "Run: ./build.sh"
