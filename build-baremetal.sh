#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="build-baremetal"
BUILD_TYPE="Release"
GENERATOR=""
JOBS=""
CLEAN=0
MAP_AND_LIST=0
COMPILER="both"
TARGET="emu"
CPU=""
CLANG_CXX="/usr/bin/clang++-20"
CLANG_CC="/usr/bin/clang-20"
ARM_GXX="/usr/bin/arm-none-eabi-g++"
ARM_GCC="/usr/bin/arm-none-eabi-gcc"
OBJDUMP="/usr/bin/arm-none-eabi-objdump"
CMSIS_DIR=""
CMSIS_GIT_TAG="v6.3.0"

usage() {
    cat <<'EOF'
Usage: ./build-baremetal.sh [options]

Options:
  -d, --build-dir <dir>        Build directory prefix (default: build-baremetal)
  -t, --type <type>            CMAKE_BUILD_TYPE (default: Release)
  -G, --generator <name>       CMake generator (default: Ninja if available)
  -j, --jobs <n>               Parallel build jobs
  -c, --clean                  Remove build directory before configure
      --map-and-list           Generate linker map and full disassembly listings
      --target <name>          Target: emu, cortex-m0, or cortex-m0plus (default: emu)
      --compiler <name>        Compiler to use: clang, gcc, or both (default: both)
      --cpu <cpu>              ARM CPU for -mcpu (default: target-selected)
      --clang-cxx <path>       clang++ path (default: /usr/bin/clang++-20)
      --clang-cc <path>        clang C path (default: /usr/bin/clang-20)
      --arm-gxx <path>         arm-none-eabi-g++ path (default: /usr/bin/arm-none-eabi-g++)
      --arm-gcc <path>         arm-none-eabi-gcc path (default: /usr/bin/arm-none-eabi-gcc)
      --objdump <path>         objdump path (default: /usr/bin/arm-none-eabi-objdump)
      --cmsis-dir <path>       Installed CMSIS_6 checkout path
      --cmsis-git-tag <tag>    CMSIS_6 tag for the CMake-managed clone (default: v6.3.0)
  -h, --help                   Show this help

This builds the MMCU_PLATFORM=mcu bare-metal platform (see docs/configure.md).
CPU flags, freestanding compile flags, and the linker entry symbol are
computed by cmake/toolchains/arm-none-eabi-{gcc,clang}.cmake from
MMCU_TARGET, not by this script.

Outputs:
  clang builds into <build-dir>-clang when --compiler=both, otherwise <build-dir>
  gcc builds into <build-dir>-gcc when --compiler=both, otherwise <build-dir>
  --map-and-list writes mmcu_app.map, mmcu_app.lst, and object .lst files under <build-dir>/listings
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--build-dir)
            BUILD_DIR="${2:-}"
            shift 2
            ;;
        -t|--type)
            BUILD_TYPE="${2:-}"
            shift 2
            ;;
        -G|--generator)
            GENERATOR="${2:-}"
            shift 2
            ;;
        -j|--jobs)
            JOBS="${2:-}"
            shift 2
            ;;
        -c|--clean)
            CLEAN=1
            shift
            ;;
        --map-and-list)
            MAP_AND_LIST=1
            shift
            ;;
        --target)
            TARGET="${2:-}"
            shift 2
            ;;
        --compiler)
            COMPILER="${2:-}"
            shift 2
            ;;
        --cpu)
            CPU="${2:-}"
            shift 2
            ;;
        --clang-cxx)
            CLANG_CXX="${2:-}"
            shift 2
            ;;
        --clang-cc)
            CLANG_CC="${2:-}"
            shift 2
            ;;
        --arm-gxx)
            ARM_GXX="${2:-}"
            shift 2
            ;;
        --arm-gcc)
            ARM_GCC="${2:-}"
            shift 2
            ;;
        --objdump)
            OBJDUMP="${2:-}"
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

if [[ -z "$GENERATOR" ]] && command -v ninja >/dev/null 2>&1; then
    GENERATOR="Ninja"
fi

case "$TARGET" in
    emu|cortex-m0|cortex-m0plus)
        ;;
    *)
        echo "Error: --target must be one of: emu, cortex-m0, cortex-m0plus" >&2
        exit 1
        ;;
esac

configure_and_build() {
    local name="$1"
    local toolchain_file="$2"
    local out_dir="$3"
    shift 3
    local extra_cmake_args=("$@")

    if [[ $MAP_AND_LIST -eq 1 ]] && [[ ! -x "$OBJDUMP" ]]; then
        echo "Error: objdump not found or not executable: $OBJDUMP" >&2
        exit 1
    fi

    if [[ $CLEAN -eq 1 ]]; then
        rm -rf "$out_dir"
    fi

    local cmake_args=(
        -S .
        -B "$out_dir"
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
        -DMMCU_PLATFORM=mcu
        -DMMCU_TARGET="$TARGET"
        -DCMAKE_TOOLCHAIN_FILE="$SCRIPT_DIR/cmake/toolchains/$toolchain_file"
        -DMMCU_CMSIS_GIT_TAG="$CMSIS_GIT_TAG"
        "${extra_cmake_args[@]}"
    )
    if [[ -n "$CPU" ]]; then
        cmake_args+=(-DMMCU_CPU="$CPU")
    fi
    if [[ -n "$CMSIS_DIR" ]]; then
        cmake_args+=(-DMMCU_CMSIS_DIR="$CMSIS_DIR")
    fi
    if [[ $MAP_AND_LIST -eq 1 ]]; then
        cmake_args+=(-DMMCU_LINKER_MAP=ON)
    fi
    if [[ -n "$GENERATOR" ]]; then
        cmake_args+=(-G "$GENERATOR")
    fi

    echo "==> Configuring $name bare-metal build in $out_dir"
    cmake "${cmake_args[@]}"

    local build_args=(--build "$out_dir")
    if [[ -n "$JOBS" ]]; then
        build_args+=(--parallel "$JOBS")
    fi

    echo "==> Building $name bare-metal target"
    cmake "${build_args[@]}"

    if [[ $MAP_AND_LIST -eq 1 ]]; then
        generate_listings "$out_dir"
    fi
}

generate_listings() {
    local out_dir="$1"
    local app_path="$out_dir/mmcu_app"
    local listing_dir="$out_dir/listings"

    if [[ ! -f "$app_path" ]]; then
        app_path="$out_dir/$BUILD_TYPE/mmcu_app"
    fi
    if [[ ! -f "$app_path" ]]; then
        echo "Error: built executable not found for listing generation in $out_dir" >&2
        exit 1
    fi

    mkdir -p "$listing_dir"
    echo "==> Writing ELF disassembly listing: $listing_dir/mmcu_app.lst"
    "$OBJDUMP" -D -S -C -w "$app_path" > "$listing_dir/mmcu_app.lst"

    echo "==> Writing object disassembly listings under $listing_dir/objects"
    mkdir -p "$listing_dir/objects"
    while IFS= read -r -d '' object_path; do
        local object_name
        object_name="${object_path#"$out_dir"/}"
        object_name="${object_name//\//__}"
        "$OBJDUMP" -D -S -C -w "$object_path" > "$listing_dir/objects/$object_name.lst"
    done < <(find "$out_dir" -type f -name '*.obj' -print0)

    if [[ -f "$out_dir/mmcu_app.map" ]]; then
        echo "==> Wrote linker map: $out_dir/mmcu_app.map"
    fi
}

case "$COMPILER" in
    clang)
        if [[ ! -x "$CLANG_CXX" ]]; then
            echo "Error: C++ compiler not found or not executable: $CLANG_CXX" >&2
            exit 1
        fi
        if [[ ! -x "$CLANG_CC" ]]; then
            echo "Error: C compiler not found or not executable: $CLANG_CC" >&2
            exit 1
        fi
        configure_and_build "clang" "arm-none-eabi-clang.cmake" "$BUILD_DIR" \
            -DMMCU_CLANG_CXX="$CLANG_CXX" \
            -DMMCU_CLANG_CC="$CLANG_CC"
        ;;
    gcc)
        if [[ ! -x "$ARM_GXX" ]]; then
            echo "Error: C++ compiler not found or not executable: $ARM_GXX" >&2
            exit 1
        fi
        if [[ ! -x "$ARM_GCC" ]]; then
            echo "Error: C compiler not found or not executable: $ARM_GCC" >&2
            exit 1
        fi
        configure_and_build "gcc" "arm-none-eabi-gcc.cmake" "$BUILD_DIR" \
            -DMMCU_ARM_GXX="$ARM_GXX" \
            -DMMCU_ARM_GCC="$ARM_GCC"
        ;;
    both)
        if [[ ! -x "$CLANG_CXX" ]]; then
            echo "Error: C++ compiler not found or not executable: $CLANG_CXX" >&2
            exit 1
        fi
        if [[ ! -x "$CLANG_CC" ]]; then
            echo "Error: C compiler not found or not executable: $CLANG_CC" >&2
            exit 1
        fi
        if [[ ! -x "$ARM_GXX" ]]; then
            echo "Error: C++ compiler not found or not executable: $ARM_GXX" >&2
            exit 1
        fi
        if [[ ! -x "$ARM_GCC" ]]; then
            echo "Error: C compiler not found or not executable: $ARM_GCC" >&2
            exit 1
        fi
        configure_and_build "clang" "arm-none-eabi-clang.cmake" "$BUILD_DIR-clang" \
            -DMMCU_CLANG_CXX="$CLANG_CXX" \
            -DMMCU_CLANG_CC="$CLANG_CC"
        configure_and_build "gcc" "arm-none-eabi-gcc.cmake" "$BUILD_DIR-gcc" \
            -DMMCU_ARM_GXX="$ARM_GXX" \
            -DMMCU_ARM_GCC="$ARM_GCC"
        ;;
    *)
        echo "Error: --compiler must be one of: clang, gcc, both" >&2
        exit 1
        ;;
esac
