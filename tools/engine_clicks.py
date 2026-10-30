"""Write a chain of engine .cfg files that right-click the ground like a player.

Each click sends the client's own right-click command (`cmd smartpoint X Y`),
the same string the client sends when the mouse button goes down on terrain,
so it exercises the real input path (unlike IssuePointOrder from a script).
The clicks walk a square of the given half-size around (cx, cy), re-clicking
every `every` client frames, and press 1 every third click so level-up cards
never pause the run.

Usage: python tools/engine_clicks.py <name> <cx> <cy> <half> <start> <every> <count>
Writes engine/dist/windows/share/warcraft-3/<name>.cfg (+ <name>_N.cfg parts);
start it with +exec <name>.cfg.
"""
import os
import sys

WAITS_PER_FILE = 250
SHARE = os.path.join(os.path.dirname(__file__), '..', 'engine', 'dist', 'windows', 'share', 'warcraft-3')


def lines(cx, cy, half, start, every, count):
    corners = [(cx + half, cy + half), (cx - half, cy + half), (cx - half, cy - half), (cx + half, cy - half)]
    for _ in range(start):
        yield 'wait'
    for k in range(count):
        x, y = corners[(k // 6) % 4]
        yield 'cmd smartpoint %d %d' % (x, y)
        if k % 3 == 0:
            yield 'oskey 49 1 0'
            yield 'wait'
            yield 'oskey 49 0 0'
        for _ in range(every):
            yield 'wait'


def main():
    name = sys.argv[1]
    cx, cy, half, start, every, count = (int(v) for v in sys.argv[2:8])
    parts, current, waits = [], [], 0
    for line in lines(cx, cy, half, start, every, count):
        current.append(line)
        if line == 'wait':
            waits += 1
            if waits >= WAITS_PER_FILE:
                parts.append(current)
                current, waits = [], 0
    parts.append(current)
    for i, body in enumerate(parts):
        file_name = name if i == 0 else '%s_%d' % (name, i)
        if i + 1 < len(parts):
            body = body + ['exec %s_%d.cfg' % (name, i + 1)]
        with open(os.path.join(SHARE, file_name + '.cfg'), 'w', newline='\n') as f:
            f.write('\n'.join(body) + '\n')
    print('wrote %d files for %s' % (len(parts), name))


if __name__ == '__main__':
    main()
