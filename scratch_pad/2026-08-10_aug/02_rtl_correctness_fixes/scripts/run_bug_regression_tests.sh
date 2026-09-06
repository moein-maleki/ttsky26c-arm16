#!/usr/bin/env bash

set -u

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../../.." && pwd)"
container_image="sha256:bd8c96069d9a5649bc6ca20a4e9c9eb4f9315725fce17fd1dc6dcf7f203c9120"

if ! command -v iverilog >/dev/null 2>&1 || ! command -v vvp >/dev/null 2>&1; then
    if ! command -v docker >/dev/null 2>&1; then
        printf '%s\n' 'ERROR: Icarus Verilog and Docker are not available.'
        exit 1
    fi

    exec docker run --rm \
        -v "$repo_root:/work" \
        -w /work \
        "$container_image" \
        bash scratch_pad/2026-08-10_aug/02_rtl_correctness_fixes/scripts/run_bug_regression_tests.sh
fi

cd "$repo_root"

test_tmp_dir="$(mktemp -d /tmp/computer-architecture-lab-regression.XXXXXX)"
trap 'rm -rf "$test_tmp_dir"' EXIT

result=0

run_version() {
    local version="$1"
    local output_file="$test_tmp_dir/${version}.vvp"
    local -a sources

    mapfile -t sources < <(
        find "$version" -maxdepth 1 -type f -name '*.v' \
            ! -name 'testbench.v' \
            ! -name 'bug_regression_testbench.v' \
            ! -name 'cache_controller_testbench.v' \
            ! -name 'sram_controller_testbench.v' \
            | sort
    )
    sources+=("$version/bug_regression_testbench.v")

    printf 'COMPILE: %s directed regression\n' "$version"
    if ! iverilog -g2005-sv -Wall -s bug_regression_testbench \
        -o "$output_file" "${sources[@]}"; then
        result=1
        return
    fi

    printf 'SIMULATE: %s directed regression\n' "$version"
    if ! timeout 30s vvp -n "$output_file"; then
        result=1
    fi
}

run_version arm-base
run_version arm-forwarding
run_version arm-cache

exit "$result"
