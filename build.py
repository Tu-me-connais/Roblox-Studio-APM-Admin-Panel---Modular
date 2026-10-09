"""Build reproducible APM preview artifacts without changing Studio or runtime code.

Requires Python 3.10+ and lxml. Run `python build.py --output dist` from a clone.
In the Codex work/apm-evolution layout the default output is ../../outputs.
The XML builder uses the primitive AttributesSerialize layout documented by:
https://github.com/rojo-rbx/rbx-dom/blob/master/docs/attributes.md
https://github.com/rojo-rbx/rbx-dom/blob/master/docs/xml.md

The generated Rojo project requires Rojo >= 7.5 for its explicit syncRules.
https://github.com/rojo-rbx/rojo/blob/master/CHANGELOG.md
XML/ZIP verification is local; it does not certify Studio import/publication.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import struct
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from lxml import etree

ROOT = Path(__file__).resolve().parent
FIXED_ZIP_TIME = (2026, 1, 1, 0, 0, 0)
SERVER = "src/ServerScriptService/APM_Server"
SHARED = "src/ReplicatedStorage/APM_Shared"
CLIENT = "src/StarterPlayer/StarterPlayerScripts/APM_Client"
LOCAL_SOURCES = {
    f"{CLIENT}/APM_Boot.luau",
    f"{CLIENT}/APM_Notices.luau",
    "src/StarterPlayer/StarterPlayerScripts/Recovery.luau",
}
OBSOLETE = {
    f"{SERVER}/APM_Boot.luau", "src/APM_Installer.luau",
    "src/READ ME___.luau", "src/manifest.json",
}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def source_text(data: bytes) -> str:
    return data.decode("utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")


def string_bytes(value: str) -> bytes:
    encoded = value.encode("utf-8")
    return struct.pack("<I", len(encoded)) + encoded


def encode_attributes(attributes: dict[str, Any]) -> bytes:
    encoded = bytearray(struct.pack("<I", len(attributes)))
    for name, value in sorted(attributes.items()):
        encoded += string_bytes(name)
        if isinstance(value, bool):
            encoded += b"\x03" + (b"\x01" if value else b"\x00")
        elif isinstance(value, (int, float)):
            encoded += b"\x06" + struct.pack("<d", value)
        elif isinstance(value, str):
            encoded += b"\x02" + string_bytes(value)
        else:
            raise TypeError(f"Unsupported attribute {name!r}")
    return bytes(encoded)


def decode_attributes(data: bytes) -> dict[str, Any]:
    """Independent bounded reader for the primitive format emitted above."""
    offset = 0

    def take(size: int) -> bytes:
        nonlocal offset
        result = data[offset:offset + size]
        if len(result) != size:
            raise ValueError("Truncated attribute data")
        offset += size
        return result

    def read_string() -> str:
        return take(struct.unpack("<I", take(4))[0]).decode("utf-8")

    output: dict[str, Any] = {}
    count = struct.unpack("<I", take(4))[0]
    for _ in range(count):
        name = read_string()
        type_id = take(1)[0]
        if type_id == 0x03:
            flag = take(1)
            if flag not in (b"\x00", b"\x01"):
                raise ValueError("Invalid bool attribute")
            value = flag == b"\x01"
        elif type_id == 0x06:
            value = struct.unpack("<d", take(8))[0]
        elif type_id == 0x02:
            value = read_string()
        else:
            raise ValueError(f"Unexpected attribute type {type_id}")
        if name in output:
            raise ValueError("Duplicate attribute")
        output[name] = value
    if offset != len(data):
        raise ValueError("Trailing attribute bytes")
    return output


@dataclass
class Node:
    name: str
    class_name: str = "Folder"
    source: str | None = None
    disabled: bool | None = None
    attributes: dict[str, Any] = field(default_factory=dict)
    children: list["Node"] = field(default_factory=list)
    value: str | None = None


class Build:
    def __init__(self, output: Path):
        self.output = output.resolve()
        self.inputs: dict[str, bytes] = {}
        self.artifacts: dict[str, bytes] = {}
        self.xml_records: dict[str, list[dict[str, Any]]] = {}
        self.value_records: dict[str, list[dict[str, Any]]] = {}
        self.output.mkdir(parents=True, exist_ok=True)

    def read(self, relative: str) -> bytes:
        if relative not in self.inputs:
            path = ROOT / relative
            if not path.is_file():
                raise FileNotFoundError(f"Missing input: {relative}")
            self.inputs[relative] = path.read_bytes()
        return self.inputs[relative]

    def script(self, name: str, source: str, class_name: str = "ModuleScript",
               disabled: bool | None = None, attributes: dict | None = None) -> Node:
        self.read(source)
        if class_name in {"Script", "LocalScript"} and disabled is None:
            disabled = False
        return Node(name, class_name, source, disabled, attributes or {})

    def directory(self, name: str, relative: str, excluded: set[str] | None = None) -> Node:
        excluded = excluded or set()
        directory = ROOT / relative
        if not directory.is_dir():
            raise FileNotFoundError(f"Missing source folder: {relative}")
        sources = {p.stem: p for p in directory.glob("*.luau") if p.name not in excluded}
        folders = {p.name: p for p in directory.iterdir() if p.is_dir()}
        result = Node(name)
        for child_name in sorted(set(sources) | set(folders)):
            path = sources.get(child_name)
            if path:
                source = path.relative_to(ROOT).as_posix()
                kind = "LocalScript" if source in LOCAL_SOURCES else "ModuleScript"
                child = self.script(child_name, source, kind)
            else:
                child = Node(child_name)
            if child_name in folders:
                nested = self.directory(child_name, folders[child_name].relative_to(ROOT).as_posix())
                child.children = nested.children
            result.children.append(child)
        return result

    def release(self) -> dict[str, Any]:
        release_text = source_text(self.read("Release.luau"))
        version_text = source_text(self.read(f"{SERVER}/Core/Version.luau"))
        if release_text != version_text:
            raise ValueError("Release.luau and Server.Core.Version.luau differ")
        # These two declarative modules are intentionally identical. This reader
        # accepts only their known string/integer fields, not arbitrary Luau code.
        expected = {
            "Version": "2.1.0-preview.1", "Channel": "experimental",
            "CoreApiVersion": 1, "ExtensionApiVersion": 1,
            "BootstrapApiVersion": 1, "InstallationSchema": 3,
            "ExtensionsSchema": 1, "DataSchemaVersion": 2,
        }
        found: dict[str, Any] = {}
        for key, literal in re.findall(r'^\s*(\w+)\s*=\s*("[^"\n]*"|\d+)\s*,?\s*$', release_text, re.M):
            if key in found:
                raise ValueError(f"Duplicate release field {key}")
            found[key] = json.loads(literal)
        if found != expected:
            raise ValueError(f"Unsupported preview release: {found!r}")
        return found

    def core(self, release: dict) -> Node:
        core = Node("APM_Core", "Model", attributes={
            "APMCore": True, "APMVersion": release["Version"],
            "APMChannel": release["Channel"], "APMInstallationSchema": release["InstallationSchema"],
            "APMLicense": "MIT",
        })
        templates = Node("ClientTemplates", children=[
            self.directory("APM_Client", CLIENT, {"APM_Notices.luau"}),
            self.script("Recovery", "src/StarterPlayer/StarterPlayerScripts/Recovery.luau", "LocalScript"),
            self.script("APM_Notices", f"{CLIENT}/APM_Notices.luau", "LocalScript"),
        ])
        core.children = [
            self.directory("Server", SERVER, {"APM_Boot.luau"}),
            self.directory("Shared", SHARED), templates,
            self.script("Bootstrap", "Bootstrap.luau"),
            self.script("Release", "Release.luau"),
            self.script("Migrations", "Migrations.luau"),
            Node("LICENSE", "StringValue", value=self.read("LICENSE").decode("utf-8")),
        ]
        return core

    def extensions(self, release: dict) -> Node:
        config = Node("Config", children=[
            self.script("ServerSettings", "extensions/ServerSettings.luau"),
            self.script("SharedConfig", "extensions/SharedConfig.luau"),
        ])
        return Node("APM_Extensions", attributes={"APMExtensionsSchema": release["ExtensionsSchema"]},
                    children=[config] + [Node(name) for name in ("Commands", "Adapters", "Server", "ClientPages")])

    def bootstrap(self, release: dict, disabled: bool) -> Node:
        return self.script("APM_Bootstrap", "installation/APM_Bootstrap.server.luau", "Script", disabled,
                           {"APMBootstrapApi": release["BootstrapApiVersion"], "AllowExperimental": True})

    def xml(self, artifact: str, root_node: Node) -> bytes:
        document = etree.Element("roblox", version="4", nsmap={
            "xmime": "http://www.w3.org/2005/05/xmlmime", "xsi": "http://www.w3.org/2001/XMLSchema-instance"})
        etree.SubElement(document, "External").text = "null"
        etree.SubElement(document, "External").text = "nil"
        counter = 0
        expected: dict[str, Node] = {}
        records: list[dict] = []
        values: list[dict] = []

        def emit(parent: etree._Element, node: Node, prefix: str = "") -> None:
            nonlocal counter
            path = f"{prefix}.{node.name}" if prefix else node.name
            if path in expected:
                raise ValueError(f"Duplicate instance: {path}")
            expected[path] = node
            counter += 1
            element = etree.SubElement(parent, "Item", {"class": node.class_name, "referent": f"APM_{counter:04d}"})
            properties = etree.SubElement(element, "Properties")
            etree.SubElement(properties, "string", name="Name").text = node.name
            etree.SubElement(properties, "bool", name="Archivable").text = "true"
            if node.attributes:
                encoded = encode_attributes(node.attributes)
                if decode_attributes(encoded) != node.attributes:
                    raise ValueError(f"Attribute encode failed: {path}")
                etree.SubElement(properties, "BinaryString", name="AttributesSerialize").text = base64.b64encode(encoded).decode("ascii")
            if node.source:
                text = source_text(self.read(node.source))
                etree.SubElement(properties, "ProtectedString", name="Source").text = etree.CDATA(text)
                records.append({"Path": path, "Class": node.class_name, "SourcePath": node.source,
                                "Disabled": node.disabled, "SourceSHA256": sha(text.encode("utf-8"))})
            if node.disabled is not None:
                if node.class_name not in {"Script", "LocalScript"}:
                    raise ValueError(f"Disabled on non-executable instance {path}")
                etree.SubElement(properties, "bool", name="Disabled").text = "true" if node.disabled else "false"
            if node.value is not None:
                if node.class_name != "StringValue":
                    raise ValueError(f"String Value on unexpected instance {path}")
                etree.SubElement(properties, "string", name="Value").text = node.value
                if node.name == "LICENSE":
                    values.append({"Path": path, "Class": "StringValue", "SourcePath": "LICENSE",
                                   "Property": "Value", "ValueSHA256": sha(node.value.encode("utf-8"))})
            for child in node.children:
                emit(element, child, path)

        emit(document, root_node)
        data = etree.tostring(document, encoding="UTF-8", xml_declaration=True, pretty_print=True)
        parsed = etree.fromstring(data)
        seen: set[str] = set()
        referents: set[str] = set()

        def verify(element: etree._Element, prefix: str = "") -> None:
            name = element.findtext("Properties/string[@name='Name']")
            path = f"{prefix}.{name}" if prefix else name
            if path in seen or path not in expected:
                raise ValueError(f"Unexpected/duplicate XML instance {path}")
            seen.add(path)
            referent = element.get("referent")
            if not referent or referent in referents:
                raise ValueError("Duplicate/missing referent")
            referents.add(referent)
            node = expected[path]
            if element.get("class") != node.class_name:
                raise ValueError(f"Class mismatch {path}")
            blob = element.findtext("Properties/BinaryString[@name='AttributesSerialize']")
            actual_attributes = decode_attributes(base64.b64decode(blob)) if blob else {}
            if actual_attributes != node.attributes:
                raise ValueError(f"Attribute mismatch {path}")
            text = element.findtext("Properties/ProtectedString[@name='Source']")
            if node.source:
                if text != source_text(self.read(node.source)):
                    raise ValueError(f"Source fidelity failed {path}")
            elif text is not None:
                raise ValueError(f"Unexpected Source {path}")
            flag = element.findtext("Properties/bool[@name='Disabled']")
            if node.disabled is None:
                if flag is not None:
                    raise ValueError(f"Unexpected Disabled {path}")
            elif flag != ("true" if node.disabled else "false"):
                raise ValueError(f"Disabled mismatch {path}")
            if element.findtext("Properties/string[@name='Value']") != node.value:
                raise ValueError(f"StringValue fidelity failed {path}")
            for child in element.findall("Item"):
                verify(child, path)

        roots = parsed.findall("Item")
        if len(roots) != 1 or roots[0].get("class") != "Model":
            raise ValueError("Artifact must have one Model root")
        verify(roots[0])
        if seen != set(expected):
            raise ValueError("XML lost instances")
        if parsed.xpath("//Item[@class='PackageLink']"):
            raise ValueError("Local export must not fabricate PackageLink")
        if any(record["SourcePath"] in OBSOLETE for record in records):
            raise ValueError("Obsolete installation source leaked into artifact")
        self.xml_records[artifact] = records
        self.value_records[artifact] = values
        self.artifacts[artifact] = data
        return data

    def rojo_node(self, node: Node) -> dict:
        # Rojo refuses $className + $path to an individual script. Its syncRules
        # assign LocalScript to the three client entry points without renaming them.
        result: dict[str, Any] = {"$ignoreUnknownInstances": True}
        if node.source:
            result["$path"] = node.source
        else:
            result["$className"] = node.class_name
        if node.attributes:
            result["$attributes"] = {
                key: {"Bool" if isinstance(value, bool) else "Float64" if isinstance(value, (int, float)) else "String": value}
                for key, value in sorted(node.attributes.items())
            }
        if node.disabled is not None:
            result["$properties"] = {"Disabled": node.disabled}
        if node.value is not None:
            result.setdefault("$properties", {})["Value"] = node.value
        for child in node.children:
            result[child.name] = self.rojo_node(child)
        return result

    def project(self, core: Node, extensions: Node, bootstrap: Node) -> dict:
        project = {"name": "APM-2.1-preview", "emitLegacyScripts": True,
                   "syncRules": [{"pattern": relative, "use": "legacyClientScript"} for relative in sorted(LOCAL_SOURCES)],
                   "tree": {"$className": "DataModel", "$ignoreUnknownInstances": True,
                            "ServerStorage": {"$className": "ServerStorage", "$ignoreUnknownInstances": True,
                                              "APM_Core": self.rojo_node(core), "APM_Extensions": self.rojo_node(extensions)},
                            "ServerScriptService": {"$className": "ServerScriptService", "$ignoreUnknownInstances": True,
                                                    "APM_Bootstrap": self.rojo_node(bootstrap)}}}
        paths: set[str] = set()

        def verify(node: dict) -> None:
            if "$path" in node:
                relative = node["$path"]
                if "$className" in node:
                    raise ValueError("Rojo script path must not override class")
                if relative in OBSOLETE or relative in paths:
                    raise ValueError(f"Duplicate/obsolete Rojo path: {relative}")
                self.read(relative)
                paths.add(relative)
            for name, child in node.items():
                if not name.startswith("$"):
                    if not isinstance(child, dict):
                        raise ValueError(f"Invalid Rojo child {name}")
                    verify(child)

        verify(project["tree"])
        if not LOCAL_SOURCES <= paths:
            raise ValueError("Missing Rojo local entry point")
        return project

    def supplemental_inputs(self) -> None:
        for relative in ("README.md", "build.py", "NOTICE.md"):
            self.read(relative)
        for directory in ("docs", "examples", "tests", "installation", "extensions"):
            base = ROOT / directory
            if not base.is_dir():
                continue
            for path in sorted(base.rglob("*")):
                if path.is_file() and "__pycache__" not in path.parts and path.suffix not in {".pyc", ".pyo"}:
                    self.read(path.relative_to(ROOT).as_posix())
        if (ROOT / "LICENSE").is_file():
            self.read("LICENSE")

    def manifest(self, release: dict) -> dict:
        usage: dict[str, list[dict]] = {}
        for artifact, records in self.xml_records.items():
            for record in records:
                usage.setdefault(record["SourcePath"], []).append({"Artifact": artifact, **record})
        for artifact, records in self.value_records.items():
            for record in records:
                usage.setdefault(record["SourcePath"], []).append({"Artifact": artifact, **record})
        files = []
        for relative, data in sorted(self.inputs.items()):
            records = usage.get(relative, [])
            kinds = {record["Class"] for record in records}
            if len(kinds) > 1:
                raise ValueError(f"Inconsistent class for {relative}")
            category = "License" if relative == "LICENSE" else "RuntimeSource" if records else (
                "TestSource" if relative.startswith("tests/") else
                "Example" if relative.startswith("examples/") else
                "InstallationProcedure" if relative.startswith("installation/") else
                "BuildTool" if relative == "build.py" else
                "RojoProject" if relative == "default.project.json" else
                "Documentation")
            files.append({"Path": relative, "Class": next(iter(kinds), None), "Kind": category,
                          "Bytes": len(data), "SHA256": sha(data), "Instances": records})
        return {"ManifestSchema": 1, "Release": release, "Files": files,
                "SourceCountCore": len(self.xml_records["APM-Core-2.1-preview.rbxmx"]),
                "Artifacts": [{"Path": name, "Bytes": len(data), "SHA256": sha(data)} for name, data in sorted(self.artifacts.items())],
                "Validation": {"XMLReparse": True, "AttributeRoundTrip": True, "ClassAndDisabledChecks": True,
                               "SourceSHA256RoundTrip": True, "ReleaseAndVersionIdentical": True,
                               "FullMITLicenseValueRoundTrip": True,
                               "RojoPathsAndMappingChecked": True, "RojoCLICompilation": "Not run by this builder",
                               "StudioArtifactImport": "Requires separate verification",
                               "RobloxPackagePublished": False},
                "ManifestSelfHash": "Excluded to avoid self-reference; every other archive file is listed."}

    def write_and_verify_zip(self, filename: str, manifest_data: bytes) -> None:
        members = {**self.inputs, "manifest.generated.json": manifest_data}
        target = self.output / filename
        with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for relative, data in sorted(members.items()):
                info = zipfile.ZipInfo(relative, FIXED_ZIP_TIME)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.create_system = 3
                info.external_attr = 0o100644 << 16
                archive.writestr(info, data, compresslevel=9)
        with zipfile.ZipFile(target) as archive:
            if archive.testzip() is not None:
                raise ValueError("ZIP CRC failure")
            names = archive.namelist()
            if len(names) != len(set(names)) or set(names) != set(members):
                raise ValueError("Duplicate/missing ZIP member")
            if set(names) & OBSOLETE:
                raise ValueError("Obsolete sources in GitHub archive")
            parsed_manifest = json.loads(archive.read("manifest.generated.json"))
            for record in parsed_manifest["Files"]:
                data = archive.read(record["Path"])
                if sha(data) != record["SHA256"] or len(data) != record["Bytes"]:
                    raise ValueError(f"ZIP source fidelity failed {record['Path']}")
            for relative, expected in members.items():
                if archive.read(relative) != expected:
                    raise ValueError(f"ZIP changed input {relative}")

    def run(self) -> dict:
        release = self.release()
        core = self.core(release)
        extensions = self.extensions(release)
        bootstrap = self.bootstrap(release, True)
        distribution = Node("APM_Distribution", "Model", attributes={
            "APMDistributionSchema": release["InstallationSchema"], "APMVersion": release["Version"], "APMLicense": "MIT"},
            children=[core, extensions, bootstrap, self.script("Installer", "installation/Install.luau", "Script", True)])
        self.xml("APM-Core-2.1-preview.rbxmx", core)
        self.xml("APM-Distribution-2.1-preview.rbxmx", distribution)
        for name, data in self.artifacts.items():
            (self.output / name).write_bytes(data)
        # The Rojo description represents an installed layout. Its bootstrap is
        # intentionally disabled, so importing/syncing code does not start it.
        project_data = json_bytes(self.project(core, extensions, bootstrap))
        (ROOT / "default.project.json").write_bytes(project_data)
        self.inputs["default.project.json"] = project_data
        gitignore = ROOT / ".gitignore"
        if not gitignore.is_file():
            gitignore.write_text("dist/\n__pycache__/\n*.py[cod]\n.venv/\n", encoding="utf-8", newline="\n")
        self.read(".gitignore")
        self.supplemental_inputs()
        metadata = self.manifest(release)
        manifest_data = json_bytes(metadata)
        (ROOT / "manifest.generated.json").write_bytes(manifest_data)
        (self.output / "APM-Manifest-2.1-preview.json").write_bytes(manifest_data)
        self.write_and_verify_zip("APM-GitHub-2.1-preview.zip", manifest_data)
        return {"Version": release["Version"], "Channel": release["Channel"],
                "CoreSourceCount": metadata["SourceCountCore"],
                "DistributionSourceCount": len(self.xml_records["APM-Distribution-2.1-preview.rbxmx"]),
                "ArchiveFiles": len(metadata["Files"]) + 1,
                "LicenseIncluded": "LICENSE" in self.inputs,
                "OutputDirectory": str(self.output),
                "Checks": "XML, attributes, classes, Disabled, source hashes, Release consistency, Rojo mapping, ZIP CRC and file hashes verified locally"}


def main() -> None:
    default_output = ROOT.parent.parent / "outputs" if ROOT.parent.name == "work" else ROOT / "dist"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=default_output)
    arguments = parser.parse_args()
    print(json.dumps(Build(arguments.output).run(), ensure_ascii=False))


if __name__ == "__main__":
    main()
