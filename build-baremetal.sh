#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR="build-baremetal"
BUILD_TYPE="Release"
GENERATOR=""
JOBS=""
CLEAN=0
MAP_AND_LIST=0
COMPILER="both"
CPU="cortex-m3"
CLANG_CXX="/usr/bin/clang++-20"
ARM_GXX="/usr/bin/arm-none-eabi-g++"
OBJDUMP="/usr/bin/arm-none-eabi-objdump"

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
      --compiler <name>        Compiler to use: clang, gcc, or both (default: both)
      --cpu <cpu>              ARM CPU for -mcpu (default: cortex-m3)
      --clang-cxx <path>       clang++ path (default: /usr/bin/clang++-20)
      --arm-gxx <path>         arm-none-eabi-g++ path (default: /usr/bin/arm-none-eabi-g++)
      --objdump <path>         objdump path (default: /usr/bin/arm-none-eabi-objdump)
  -h, --help                   Show this help

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
        --arm-gxx)
            ARM_GXX="${2:-}"
            shift 2
            ;;
        --objdump)
            OBJDUMP="${2:-}"
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

COMMON_CXX_FLAGS=(
    -mcpu="$CPU"
    -mthumb
    -ffreestanding
    -fdata-sections
    -ffunction-sections
    -fno-exceptions
    -fno-rtti
    -fno-use-cxa-atexit
)
COMMON_LINK_FLAGS=(
    -mcpu="$CPU"
    -mthumb
    -nostdlib
    -Wl,--gc-sections
)

join_flags() {
    local flags=("$@")
    printf '%s ' "${flags[@]}"
}

configure_and_build() {
    local name="$1"
    local compiler="$2"
    local out_dir="$3"
    local entry_symbol="$4"
    shift 4
    local extra_cmake_args=("$@")

    if [[ ! -x "$compiler" ]]; then
        echo "Error: compiler not found or not executable: $compiler" >&2
        exit 1
    fi
    if [[ $MAP_AND_LIST -eq 1 ]] && [[ ! -x "$OBJDUMP" ]]; then
        echo "Error: objdump not found or not executable: $OBJDUMP" >&2
        exit 1
    fi

    if [[ $CLEAN -eq 1 ]]; then
        rm -rf "$out_dir"
    fi

    local cxx_flags link_flags
    cxx_flags="$(join_flags "${COMMON_CXX_FLAGS[@]}")"
    link_flags="$(join_flags "${COMMON_LINK_FLAGS[@]}" -Wl,-e,"$entry_symbol")"
    if [[ $MAP_AND_LIST -eq 1 ]]; then
        link_flags+="$(join_flags -Wl,-Map,mmcu_app.map -Wl,--cref)"
    fi

    local cmake_args=(
        -S .
        -B "$out_dir"
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
        -DCMAKE_SYSTEM_NAME=Generic
        -DCMAKE_SYSTEM_PROCESSOR=arm
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
        -DCMAKE_CXX_COMPILER="$compiler"
        -DCMAKE_CXX_FLAGS_INIT="$cxx_flags"
        -DCMAKE_EXE_LINKER_FLAGS_INIT="$link_flags"
        "${extra_cmake_args[@]}"
    )
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
        configure_and_build "clang" "$CLANG_CXX" "$BUILD_DIR" "_Z4mainv" -DCMAKE_CXX_COMPILER_TARGET=arm-none-eabi
        ;;
    gcc)
        configure_and_build "gcc" "$ARM_GXX" "$BUILD_DIR" "main"
        ;;
    both)
        configure_and_build "clang" "$CLANG_CXX" "$BUILD_DIR-clang" "_Z4mainv" -DCMAKE_CXX_COMPILER_TARGET=arm-none-eabi
        configure_and_build "gcc" "$ARM_GXX" "$BUILD_DIR-gcc" "main"
        ;;
    *)
        echo "Error: --compiler must be one of: clang, gcc, both" >&2
        exit 1
        ;;
esac
