#!/usr/bin/env python
import sys
from subprocess import call

def write_stdout(s):
    sys.stdout.write(s)
    sys.stdout.flush()

def main():
    while 1:
        write_stdout('READY\n')
        line = sys.stdin.readline()
        call(["kill", "1"])
        write_stdout('RESULT 2\nOK')

if __name__ == '__main__':
    main()

