"""Generate or check the Rojo description of the exported active APM kit.

Python 3.10+; standard library only. Run ``python build.py`` to generate
default.project.json, or ``python build.py --check`` to validate it without
writing files. Sources are read as bytes and are never rewritten or executed.
This validates the export on disk; it does not run APM or contact Studio.

Rojo 7.5+ is required for explicit per-file syncRules. Rojo forbids combining
$className with $path for a script, so its class is set by the syncRule instead.
References: https://rojo.space/docs/v7/project-format/ and the Rojo source at
https://github.com/rojo-rbx/rojo/blob/master/src/snapshot_middleware/project.rs
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path, PurePosixPath
from typing import Any


ROOT = Path(__file__).resolve().parent
KIT_ROOT = "Workspace.APM_DistributionKits.APM_Kit"
CLASSES = {"Model", "Folder", "ModuleScript", "Script", "LocalScript", "StringValue"}
SCRIPT_CLASSES = {"ModuleScript", "Script", "LocalScript"}
SCRIPT_RULES = {
    "ModuleScript": "moduleScript",
    "Script": "legacyServerScript",
    "LocalScript": "legacyClientScript",
}
RUN_CONTEXTS = {"Legacy", "Server", "Client"}


class ExportError(ValueError):
    """The export cannot be represented or checked faithfully."""


def unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ExportError(f"Duplicate JSON key: {key!r}")
        result[key] = value
    return result


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ExportError(f"Cannot read {path.name}: {error}") from error


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n").encode("utf-8")


def label(path: tuple[str, ...]) -> str:
    return ".".join((KIT_ROOT, *path))


def attribute_value(value: Any, name: str) -> dict[str, Any]:
    if isinstance(value, bool):
        return {"Bool": value}
    if isinstance(value, (int, float)) and math.isfinite(value):
        return {"Float64": value}
    if isinstance(value, str):
        return {"String": value}
    raise ExportError(f"Unsupported attribute value for {name}; an explicit export format is required")


def source_path(root: Path, relative: Any) -> tuple[str, Path]:
    if not isinstance(relative, str) or not relative or "\\" in relative:
        raise ExportError("sourceFile must be a relative POSIX path")
    path = PurePosixPath(relative)
    if (path.is_absolute() or ".." in path.parts or "." in relative.split("/")
            or any(not part or ":" in part for part in relative.split("/"))
            or path.parts[:2] != ("src", "APM_Kit")
            or path.suffix != ".luau"):
        raise ExportError(f"Invalid sourceFile: {relative!r}")
    if any(character in relative for character in "*?[]{}"):
        raise ExportError(f"sourceFile contains a Rojo glob metacharacter: {relative!r}")
    target = root.joinpath(*path.parts)
    try:
        target.resolve().relative_to(root.resolve())
    except ValueError as error:
        raise ExportError(f"sourceFile escapes the repository: {relative!r}") from error
    if not target.is_file():
        raise ExportError(f"Missing source file: {relative}")
    return path.as_posix(), target


def expected_project(root: Path = ROOT) -> tuple[dict[str, Any], dict[str, Any]]:
    """Validate manifest and source index; return the deterministic Rojo tree."""
    manifest = read_json(root / "manifest.json")
    if not isinstance(manifest, dict) or manifest.get("schemaVersion") != 1:
        raise ExportError("manifest.json must have schemaVersion 1")
    if manifest.get("root") != KIT_ROOT:
        raise ExportError(f"manifest root must be {KIT_ROOT}")
    version = manifest.get("version")
    if not isinstance(version, str) or not version.strip():
        raise ExportError("manifest version must be a nonempty string")
    records = manifest.get("nodes")
    if not isinstance(records, list) or not records:
        raise ExportError("manifest nodes must be a nonempty array")

    nodes: dict[tuple[str, ...], dict[str, Any]] = {}
    source_files: set[str] = set()
    rules: list[dict[str, str]] = []
    hash_count = 0
    for record in records:
        if not isinstance(record, dict):
            raise ExportError("Every node must be an object")
        parts = record.get("path")
        if not isinstance(parts, list) or any(
            not isinstance(part, str) or not part or part.startswith("$") or "\x00" in part
            for part in parts
        ):
            raise ExportError("Node path must contain nonempty names without a reserved $ prefix")
        path = tuple(parts)
        if path in nodes:
            raise ExportError(f"Duplicate instance path: {label(path)}")
        kind = record.get("class")
        if kind not in CLASSES:
            raise ExportError(f"Unsupported class for {label(path)}: {kind!r}")
        archivable = record.get("archivable")
        if not isinstance(archivable, bool):
            raise ExportError(f"Missing or invalid archivable property: {label(path)}")
        attributes = record.get("attributes")
        if attributes == []:
            attributes = {}
        if not isinstance(attributes, dict) or any(not isinstance(key, str) or not key for key in attributes):
            raise ExportError(f"Invalid attributes: {label(path)}")
        tags = record.get("tags")
        if not isinstance(tags, list) or any(not isinstance(tag, str) or not tag for tag in tags):
            raise ExportError(f"Missing or invalid tags: {label(path)}")
        if len(tags) != len(set(tags)):
            raise ExportError(f"Duplicate tags: {label(path)}")

        result: dict[str, Any] = {"$ignoreUnknownInstances": True}
        properties: dict[str, Any] = {"Archivable": archivable}
        if kind in SCRIPT_CLASSES:
            relative, target = source_path(root, record.get("sourceFile"))
            if relative in source_files:
                raise ExportError(f"Source file used by multiple instances: {relative}")
            data = target.read_bytes()
            try:
                data.decode("utf-8")
            except UnicodeError as error:
                raise ExportError(f"Source file is not UTF-8: {relative}") from error
            expected_hash = record.get("sourceSha256")
            if expected_hash is not None:
                if not isinstance(expected_hash, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", expected_hash):
                    raise ExportError(f"Invalid sourceSha256: {relative}")
                if hashlib.sha256(data).hexdigest() != expected_hash.lower():
                    raise ExportError(f"Source SHA256 mismatch: {relative}")
                hash_count += 1
            source_files.add(relative)
            result["$path"] = relative
            rules.append({"pattern": relative, "use": SCRIPT_RULES[kind]})
        else:
            if "sourceFile" in record or "sourceSha256" in record:
                raise ExportError(f"Non-script instance has source metadata: {label(path)}")
            result["$className"] = kind
        if kind in {"Script", "LocalScript"}:
            enabled = record.get("enabled")
            if not isinstance(enabled, bool):
                raise ExportError(f"Missing or invalid enabled property: {label(path)}")
            properties["Enabled"] = enabled
        elif "enabled" in record:
            raise ExportError(f"Instance class has no Enabled property: {label(path)}")
        if kind in {"Script", "LocalScript"}:
            context = record.get("runContext")
            if isinstance(context, str):
                context = context.removeprefix("Enum.RunContext.")
            if context not in RUN_CONTEXTS:
                raise ExportError(f"Missing or invalid runContext: {label(path)}")
            properties["RunContext"] = context
        elif "runContext" in record:
            raise ExportError(f"Instance class has no RunContext property: {label(path)}")
        if kind == "StringValue":
            if not isinstance(record.get("value"), str):
                raise ExportError(f"Missing or invalid StringValue value: {label(path)}")
            properties["Value"] = record["value"]
        elif "value" in record:
            raise ExportError(f"Unexpected value property: {label(path)}")
        if attributes:
            result["$attributes"] = {
                key: attribute_value(value, f"{label(path)}.{key}")
                for key, value in sorted(attributes.items())
            }
        if tags:
            properties["Tags"] = sorted(tags)
        result["$properties"] = properties
        nodes[path] = result

    if () not in nodes:
        raise ExportError("Manifest does not describe its root instance with path []")
    for path in sorted(nodes, key=lambda value: (len(value), value)):
        if not path:
            continue
        if path[:-1] not in nodes:
            raise ExportError(f"Missing parent instance for {label(path)}")
        nodes[path[:-1]][path[-1]] = nodes[path]

    actual_files = {
        path.relative_to(root).as_posix()
        for path in (root / "src").rglob("*") if path.is_file()
    }
    extra_files = sorted(actual_files - source_files)
    if extra_files:
        raise ExportError("Files under src absent from manifest: " + ", ".join(extra_files))

    project = {
        "name": f"APM-{version}",
        "emitLegacyScripts": True,
        "syncRules": sorted(rules, key=lambda rule: rule["pattern"]),
        "tree": {
            "$className": "DataModel",
            "$ignoreUnknownInstances": True,
            "Workspace": {
                "$className": "Workspace",
                "$ignoreUnknownInstances": True,
                "APM_DistributionKits": {
                    "$className": "Folder",
                    "$ignoreUnknownInstances": True,
                    "APM_Kit": nodes[()],
                },
            },
        },
    }
    summary = {
        "version": version,
        "root": KIT_ROOT,
        "instances": len(nodes),
        "sources": len(source_files),
        "sourceHashesVerified": hash_count,
    }
    return project, summary


def run(root: Path = ROOT, *, check: bool = False) -> dict[str, Any]:
    project, summary = expected_project(root)
    target = root / "default.project.json"
    if check:
        if read_json(target) != project:
            raise ExportError("default.project.json differs from manifest; run python build.py")
    else:
        target.write_bytes(json_bytes(project))
    return {**summary, "project": target.name, "mode": "check" if check else "generate"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate sources and generated project without writing")
    arguments = parser.parse_args()
    try:
        print(json.dumps(run(check=arguments.check), ensure_ascii=False))
    except (ExportError, OSError) as error:
        print(f"Export validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
