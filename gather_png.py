import argparse
import shutil
import tkinter as tk
import typing as t
from pathlib import Path
from tkinter import filedialog


def _prompt_for_dir(start_dir: Path = Path()) -> Path:
    """Open a Tk file selection dialog to prompt the user to select a directory for processing."""
    root = tk.Tk()
    root.withdraw()

    picked = filedialog.askdirectory(
        title="Select base directory",
        initialdir=start_dir,
    )

    return Path(picked)


def gather(top_dir: Path) -> None:
    """Recursively find all `*.png` files and place into a `/plots` directory next to `top_dir`."""
    out_dir = top_dir / "plots"
    out_dir.mkdir(exist_ok=True)

    n = 0
    for file in top_dir.rglob("*.png"):
        if file.parent == out_dir:
            # Ignore files that have already been moved
            continue
        shutil.copy(file, out_dir)
        n += 1

    print(f"Copied {n} files.")


def main(argv: t.Optional[t.Sequence[str]] = None) -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("top_dir", nargs="?", type=Path, default=None)
    args = parser.parse_args(argv)

    if not args.top_dir:
        top_dir = _prompt_for_dir()
    else:
        top_dir = args.top_dir

    gather(top_dir)


if __name__ == "__main__":  # pragma: no cover
    main()
