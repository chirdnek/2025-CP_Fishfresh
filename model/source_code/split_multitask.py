# split_multitask.py
# Usage (from model/source_code):
#   python split_multitask.py --src ../datasets/_raw --dst ../datasets --train 0.6 --val 0.2 --test 0.2 --clean --move --seed 123
from __future__ import annotations
from pathlib import Path
import argparse, random, shutil, math

ALLOWED = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}

def collect(src_root: Path) -> dict[tuple[str, str], list[Path]]:
    buckets: dict[tuple[str,str], list[Path]] = {}
    if not src_root.exists():
        raise SystemExit(f"Source not found: {src_root}")
    for freshness_dir in src_root.iterdir():  # fresh / not_fresh
        if not freshness_dir.is_dir(): 
            continue
        f_name = freshness_dir.name
        for species_dir in freshness_dir.iterdir():  # species
            if not species_dir.is_dir():
                continue
            s_name = species_dir.name
            key = (f_name, s_name)
            buckets.setdefault(key, [])
            for p in species_dir.rglob("*"):
                if p.is_file() and p.suffix.lower() in ALLOWED:
                    buckets[key].append(p)
    return buckets

def split_counts(n: int, r_train: float, r_val: float, r_test: float) -> tuple[int,int,int]:
    if not (0.999 <= (r_train + r_val + r_test) <= 1.001):
        raise ValueError("Splits must sum to 1.0")
    base = [math.floor(n * r) for r in (r_train, r_val, r_test)]
    rem = n - sum(base)
    # distribute remaining items by largest fractional parts
    fracs = [n * r - b for r, b in zip((r_train, r_val, r_test), base)]
    order = sorted(range(3), key=lambda i: fracs[i], reverse=True)
    for i in order[:rem]:
        base[i] += 1
    return tuple(base)

def _clear_dir(d: Path):
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True, exist_ok=True)

def place(files: list[Path], dst_root: Path, subset: str, f_name: str, s_name: str, move: bool):
    out_dir = dst_root / subset / f_name / s_name
    out_dir.mkdir(parents=True, exist_ok=True)
    for src in files:
        dst = out_dir / src.name
        if move:
            shutil.move(str(src), str(dst))
        else:
            shutil.copy2(str(src), str(dst))

def main():
    ap = argparse.ArgumentParser(description="Split dataset into train/validation/test.")
    ap.add_argument("--src", default="../datasets/_raw", help="root of unsplit data")
    ap.add_argument("--dst", default="../datasets", help="destination datasets root")
    ap.add_argument("--train", type=float, default=0.60)
    ap.add_argument("--val",   type=float, default=0.20)
    ap.add_argument("--test",  type=float, default=0.20)
    ap.add_argument("--seed",  type=int, default=123)
    ap.add_argument("--move",  action="store_true", help="move files instead of copy")
    ap.add_argument("--clean", action="store_true", help="wipe existing train/validation/test first")
    args = ap.parse_args()

    src_root = Path(__file__).resolve().parent / args.src
    dst_root = Path(__file__).resolve().parent / args.dst

    if args.clean:
        for s in ("train","validation","test"):
            _clear_dir(dst_root / s)
    else:
        for s in ("train","validation","test"):
            (dst_root / s).mkdir(parents=True, exist_ok=True)

    random.seed(args.seed)

    buckets = collect(src_root)
    if not buckets:
        raise SystemExit(f"No images found under {src_root}")

    total = 0
    print("Splitting per (freshness, species):")
    for (f_name, s_name), files in sorted(buckets.items()):
        files = [p for p in files if p.suffix.lower() in ALLOWED]
        random.shuffle(files)
        n = len(files)
        t, v, te = split_counts(n, args.train, args.val, args.test)

        train_files = files[:t]
        val_files   = files[t:t+v]
        test_files  = files[t+v:t+v+te]

        place(train_files, dst_root, "train",      f_name, s_name, args.move)
        place(val_files,   dst_root, "validation", f_name, s_name, args.move)
        place(test_files,  dst_root, "test",       f_name, s_name, args.move)

        total += n
        print(f"  {f_name:10s} / {s_name:25s} -> "
              f"train {len(train_files):4d}, val {len(val_files):4d}, test {len(test_files):4d}  (total {n})")

    print(f"\nDone. Processed {total} files. Output: {dst_root}")

if __name__ == "__main__":
    main()
