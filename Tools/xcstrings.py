#!/usr/bin/env python3

# python3 xcstrings.py export Localizable.xcstrings en.txt
# python3 /Volumes/FData/Development/Taggd/Tools/xcstrings.py export Localizable.xcstrings en.txt
#
# python3 xcstrings.py import Localizable.xcstrings fr fr.txt
# python3 /Volumes/FData/Development/Taggd/Tools/xcstrings.py import Localizable.xcstrings es sp.txt

import json
import argparse
from pathlib import Path


def load_xcstrings(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_xcstrings(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def export_strings(xcstrings_path, output_path):
    data = load_xcstrings(xcstrings_path)

    lines = []

    for key, value in data["strings"].items():
        loc = value.get("localizations", {})
        en = loc.get("en")

        if en:
            lines.append(en["stringUnit"]["value"])
        else:
            lines.append(key)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    print(f"Exported {len(lines)} strings to {output_path}")


def import_strings(xcstrings_path, language, input_path):
    data = load_xcstrings(xcstrings_path)

    translated = Path(input_path).read_text(encoding="utf-8").splitlines()

    keys = list(data["strings"].keys())

    if len(translated) != len(keys):
        raise ValueError(
            f"Expected {len(keys)} translations but got {len(translated)}."
        )

    for key, translation in zip(keys, translated):
        if "localizations" not in data["strings"][key]:
            data["strings"][key]["localizations"] = {}

        data["strings"][key]["localizations"][language] = {
            "stringUnit": {
                "state": "translated",
                "value": translation,
            }
        }

    save_xcstrings(xcstrings_path, data)

    print(f"Imported {len(translated)} strings as '{language}'")


def main():
    parser = argparse.ArgumentParser()

    sub = parser.add_subparsers(dest="cmd", required=True)

    e = sub.add_parser("export")
    e.add_argument("xcstrings")
    e.add_argument("output")

    i = sub.add_parser("import")
    i.add_argument("xcstrings")
    i.add_argument("language")
    i.add_argument("input")

    args = parser.parse_args()

    if args.cmd == "export":
        export_strings(args.xcstrings, args.output)

    elif args.cmd == "import":
        import_strings(args.xcstrings, args.language, args.input)


if __name__ == "__main__":
    main()