import sys

import jsonc


def lint_file(path: str) -> bool:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            jsonc.load(handle)
        return True
    except Exception as exc:
        print(f"{path}: {exc}", file=sys.stderr)
        return False


def main() -> int:
    ok = True
    for path in sys.argv[1:]:
        if not lint_file(path):
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
