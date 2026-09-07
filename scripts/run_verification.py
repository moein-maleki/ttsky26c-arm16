#!/usr/bin/env python3
"""Run a complete test profile from a private copy and retain its evidence."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time


REPO = Path(__file__).resolve().parents[1]
IGNORE = shutil.ignore_patterns('sim_build', '__pycache__', '.pytest_cache', '*.fst', '*.vcd',
                               '*.vvp', 'results.xml', 'gate_level_netlist.v', 'output')
DEAD_ROM = """`default_nettype none
module demo_rom (
    input wire [15:2] address_in,
    output wire [31:0] word_out
);
    assign word_out = 32'hEAFFFFFE;
endmodule
`default_nettype wire
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('profile', choices=['software', 'rtl', 'rom', 'gate', 'dead-rom'])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--netlist', type=Path)
    parser.add_argument('--seed', type=int, default=2026)
    args = parser.parse_args()
    if args.profile == 'gate' and (args.netlist is None or not args.netlist.is_file()):
        parser.error('gate profile requires an existing --netlist')
    out = args.output.resolve()
    if out.exists() and any(out.iterdir()):
        parser.error('output directory must be new or empty; preserve prior evidence')
    out.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix=f'arm16-{args.profile}-'))
    for name in ['src', 'test', 'scripts']:
        shutil.copytree(REPO / name, work / name, ignore=IGNORE)
    shutil.copy2(REPO / 'info.yaml', work / 'info.yaml')
    if args.profile == 'gate':
        shutil.copy2(args.netlist, work / 'test/gate_level_netlist.v')
    if args.profile == 'dead-rom':
        (work / 'src/demo_rom.v').write_text(DEAD_ROM)
    manifest = {str(path.relative_to(work)): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in sorted(work.rglob('*')) if path.is_file()}
    (out / 'input_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    with tarfile.open(out / 'inputs.tar.gz', 'w:gz') as archive:
        for name in manifest:
            archive.add(work / name, arcname=name, recursive=False)
    env = os.environ.copy()
    for name in ['COCOTB_TEST_FILTER', 'COCOTB_TEST_MODULES', 'COCOTB_TESTCASE', 'TESTCASE',
                 'GATES', 'ROMTEST', 'PYTEST_ADDOPTS', 'PYTEST_PLUGINS', 'MAKEFLAGS', 'MFLAGS']:
        env.pop(name, None)
    env.update(PYTHONDONTWRITEBYTECODE='1', ARM16_NATIVE_CLOCK='1',
               ARM16_DEAD_ROM='1' if args.profile == 'dead-rom' else '0',
               ARM16_SEED=str(args.seed), ARM16_RANDOM_COUNT='200', ARM16_FLASH_RANDOM_COUNT='40')
    collected = []
    if args.profile == 'software':
        if not shutil.which('arm-none-eabi-as', path=env['PATH']) or not shutil.which('arm-none-eabi-objcopy', path=env['PATH']):
            parser.error('software profile requires GNU ARM assembler and objcopy; no skipped comparison')
        test_files = ['test/test_software.py', 'test/test_checkers.py', 'test/test_model_lifecycle.py',
                      'scripts/test_check_results.py', 'scripts/test_check_signoff.py']
        collection = subprocess.run([sys.executable, '-m', 'pytest', '-q', '-p', 'no:cacheprovider',
                                     '--collect-only', *test_files], cwd=work, env=env,
                                    capture_output=True, text=True)
        (out / 'collection.log').write_text(collection.stdout + collection.stderr)
        if collection.returncode:
            print('Software collection failed; see collection.log', flush=True)
            return 1
        collected = [line.split('::', 1)[1] for line in collection.stdout.splitlines()
                     if any(line.startswith(name + '::') for name in test_files)]
        if not collected:
            print('Software collection is empty', flush=True)
            return 1
        (out / 'collected_tests.json').write_text(json.dumps(collected, indent=2) + '\n')
        command = [sys.executable, '-m', 'pytest', '-q', '-p', 'no:cacheprovider',
                   '--junitxml=results.xml', *test_files]
        cwd = work
    else:
        command = ['make', '--no-print-directory', 'WAVES=0', 'ARM16_NATIVE_CLOCK=1',
                   'ROMTEST=' + ('yes' if args.profile == 'rtl' else 'no'),
                   'GATES=' + ('yes' if args.profile == 'gate' else 'no')]
        if args.profile == 'dead-rom':
            command.extend(['COCOTB_TEST_MODULES=test_boot_video',
                            'COCOTB_TEST_FILTER=^test_boot_video[.]test_dead_rom_rejected_by_visible_progress$'])
        cwd = work / 'test'
    (out / 'command.json').write_text(json.dumps({'command': command, 'cwd': str(cwd),
                                                  'seed': args.seed, 'profile': args.profile}, indent=2) + '\n')
    start = time.monotonic()
    print(f'Running {args.profile} in {work}; log: {out / "run.log"}', flush=True)
    with (out / 'run.log').open('w') as log:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT)
    xml = cwd / 'results.xml'
    check_code = 1
    if xml.is_file():
        shutil.copy2(xml, out / 'results.xml')
        with (out / 'result_check.log').open('w') as log:
            check_command = [sys.executable, str(work / 'scripts/check_results.py'),
                             str(xml), '--profile', args.profile, '--json-output', str(out / 'cases.json')]
            for name in collected:
                check_command.extend(['--require', name])
            checked = subprocess.run(check_command,
                                     cwd=work, env=env, stdout=log, stderr=subprocess.STDOUT)
        check_code = checked.returncode
    changed = [name for name, digest in manifest.items()
               if not (work / name).is_file() or hashlib.sha256((work / name).read_bytes()).hexdigest() != digest]
    status = {'profile': args.profile, 'process_exit': result.returncode, 'checker_exit': check_code,
              'elapsed_seconds': time.monotonic() - start, 'changed_inputs': changed, 'work': str(work),
              'passed': result.returncode == 0 and check_code == 0 and not changed}
    (out / 'status.json').write_text(json.dumps(status, indent=2) + '\n')
    generated = work / 'test/output'
    if generated.is_dir():
        shutil.copytree(generated, out / 'images')
    print(json.dumps(status), flush=True)
    if not status['passed']:
        print((out / 'result_check.log').read_text() if (out / 'result_check.log').exists() else 'No result XML', flush=True)
    return 0 if status['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
