# model/source_code/restructure_multitask.py
from pathlib import Path
from shutil import move
import sys

ALLOWED = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
FRESHNESS = ["fresh", "not_fresh"]
SPLITS = ["train", "validation", "testing"]  # handles your names

def ensure(dirpath: Path):
    dirpath.mkdir(parents=True, exist_ok=True)
    return dirpath

def main():
    root = Path(__file__).resolve().parents[1] / "datasets"
    moved = 0
    for split in SPLITS:
        split_dir = root / split
        if not split_dir.exists():
            print(f"[skip] {split_dir} (not found)")
            continue
        for fcls in FRESHNESS:
            fdir = split_dir / fcls
            if not fdir.exists():
                print(f"[skip] {fdir} (not found)")
                continue

            # 1) If there are images directly in the freshness folder, put them under 'unknown/'
            unknown_dir = ensure(fdir / "unknown")
            for p in list(fdir.iterdir()):
                if p.is_file() and p.suffix.lower() in ALLOWED:
                    # move file into unknown/
                    target = unknown_dir / p.name
                    # avoid collisions
                    i = 1
                    while target.exists():
                        target = unknown_dir / f"{p.stem}_{i}{p.suffix}"
                        i += 1
                    move(str(p), str(target))
                    moved += 1

            # 2) Ensure that any non-image children are left as species folders
            # (nothing to do; existing species subfolders stay as-is)

    print(f"✅ Done. Moved {moved} unlabeled species images into 'unknown/' folders.")
    print("   Final structure (per split): split/<fresh|not_fresh>/<species or 'unknown'>/image.jpg")
    print("   If you see 'unknown', the trainer can handle it (species list will include 'unknown').")

if __name__ == "__main__":
    sys.exit(main())
