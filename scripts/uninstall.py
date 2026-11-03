#!/usr/bin/env python3
"""Run the shared uninstaller from a source checkout or installed app directory."""
from pathlib import Path
import sys

source_root = Path(__file__).resolve().parents[1]
if (source_root/'energytlk/uninstall.py').is_file():
    sys.path.insert(0, str(source_root))
from energytlk.uninstall import main

if __name__ == '__main__':
    main()
