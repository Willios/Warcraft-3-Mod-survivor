"""Write a chain of engine .cfg files that replay scripted input.

Each step is a wait (client frames), a console command (oskey, screenshot...)
or a key press. Files stay small and chain with `exec`, because one long file
of waits overflows the engine's command buffer.

Usage: python tools/engine_flow.py <name> <steps...>
  steps: w<frames>   wait that many client frames
         k<code>     press and release a key (OS key code, e.g. k27 = Escape)
         d<code>     key down,  u<code> key up
         s           screenshot
Writes engine/dist/windows/share/warcraft-3/<name>.cfg (+ <name>_N.cfg parts);
start it with +exec <name>.cfg.
"""
import os
import sys

WAITS_PER_FILE = 300
SHARE = os.path.join(os.path.dirname(__file__), '..', 'engine', 'dist', 'windows', 'share', 'warcraft-3')


def lines_for(steps):
    for step in steps:
        kind, arg = step[0], step[1:]
        if kind == 'w':
            for _ in range(int(arg)):
                yield 'wait'
        elif kind == 'k':
            yield 'oskey %s 1 0' % arg
            yield 'wait'
            yield 'wait'
            yield 'oskey %s 0 0' % arg
        elif kind == 'd':
            yield 'oskey %s 1 0' % arg
        elif kind == 'u':
            yield 'oskey %s 0 0' % arg
        elif kind == 's':
            yield 'screenshot'
        else:
            raise SystemExit('unknown step ' + step)


def main():
    name, steps = sys.argv[1], sys.argv[2:]
    files, current, waits = [], [], 0
    for line in lines_for(steps):
        current.append(line)
        if line == 'wait':
            waits += 1
            if waits >= WAITS_PER_FILE:
                files.append(current)
                current, waits = [], 0
    files.append(current)
    names = [name] + ['%s_%d' % (name, i) for i in range(1, len(files))]
    for index, body in enumerate(files):
        text = []
        run = 0
        for line in body:
            if line == 'wait':
                run += 1
                continue
            if run:
                text.append(';'.join(['wait'] * run))
                run = 0
            text.append(line)
        if run:
            text.append(';'.join(['wait'] * run))
        if index + 1 < len(files):
            text.append('exec %s.cfg' % names[index + 1])
        with open(os.path.join(SHARE, names[index] + '.cfg'), 'w', newline='\n') as f:
            f.write('\n'.join(text) + '\n')
    print('wrote', len(files), 'files for', name)


main()
