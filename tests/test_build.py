"""Offline integrity checks for the export builder; no APM code is executed."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location("apm_build", Path(__file__).resolve().parents[1] / "build.py")
assert SPEC and SPEC.loader
build = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build)


class ExportIntegrityTests(unittest.TestCase):
    def setUp(self) -> None:
        test_root = Path(__file__).resolve().parent
        self.temporary = tempfile.TemporaryDirectory(dir=test_root, prefix=".build-test-")
        self.root = Path(self.temporary.name)
        # Keep temporary writes and the recursive cleanup inside this test folder.
        self.root.resolve().relative_to(test_root)
        self.addCleanup(self.temporary.cleanup)
        self.source = b"-- exact UTF-8 source\r\nreturn 'caf\xc3\xa9'\r\n"
        self.manifest = {
            "schemaVersion": 1,
            "version": "2.10.2",
            "root": build.KIT_ROOT,
            "nodes": [
                self.node([], "Model", attributes={"APMVersion": "2.10.2", "APM_Kit": True}),
                self.node(["Assistant"], "ModuleScript", sourceFile="src/APM_Kit/Assistant.luau"),
                self.node(["Assistant", "Parser"], "ModuleScript", sourceFile="src/APM_Kit/Assistant/Parser.luau"),
                self.node(["Installer"], "Script", sourceFile="src/APM_Kit/Installer.luau", enabled=False, runContext="Legacy"),
                self.node(["Client"], "LocalScript", sourceFile="src/APM_Kit/Client.luau", enabled=True, runContext="Legacy"),
                self.node(["LICENSE"], "StringValue", value="MIT\n"),
            ],
        }
        for node in self.manifest["nodes"]:
            if "sourceFile" in node:
                path = self.root / node["sourceFile"]
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(self.source)
                node["sourceSha256"] = hashlib.sha256(self.source).hexdigest()
        self.save()

    @staticmethod
    def node(path: list[str], kind: str, **fields: object) -> dict:
        return {"path": path, "class": kind, "attributes": [], "archivable": True, "tags": [], **fields}

    def save(self) -> None:
        (self.root / "manifest.json").write_bytes(build.json_bytes(self.manifest))

    def test_script_parent_and_child_map_once_with_exact_classes_and_properties(self) -> None:
        project, summary = build.expected_project(self.root)
        kit = project["tree"]["Workspace"]["APM_DistributionKits"]["APM_Kit"]
        self.assertEqual(kit["$className"], "Model")
        self.assertEqual(kit["Assistant"]["$path"], "src/APM_Kit/Assistant.luau")
        self.assertEqual(kit["Assistant"]["Parser"]["$path"], "src/APM_Kit/Assistant/Parser.luau")
        self.assertNotIn("$className", kit["Assistant"])
        self.assertEqual(kit["Installer"]["$properties"], {"Archivable": True, "Enabled": False, "RunContext": "Legacy"})
        self.assertEqual(kit["Client"]["$properties"], {"Archivable": True, "Enabled": True, "RunContext": "Legacy"})
        self.assertEqual(kit["LICENSE"]["$properties"]["Value"], "MIT\n")
        rules = {rule["pattern"]: rule["use"] for rule in project["syncRules"]}
        self.assertEqual(rules["src/APM_Kit/Installer.luau"], "legacyServerScript")
        self.assertEqual(rules["src/APM_Kit/Client.luau"], "legacyClientScript")
        self.assertEqual(summary["sourceHashesVerified"], 4)

    def test_generation_and_check_do_not_change_source_bytes(self) -> None:
        build.run(self.root)
        project_before = (self.root / "default.project.json").read_bytes()
        build.run(self.root, check=True)
        self.assertEqual((self.root / "default.project.json").read_bytes(), project_before)
        for node in self.manifest["nodes"]:
            if "sourceFile" in node:
                self.assertEqual((self.root / node["sourceFile"]).read_bytes(), self.source)

    def test_check_detects_changed_project_without_rewriting(self) -> None:
        build.run(self.root)
        path = self.root / "default.project.json"
        changed = json.loads(path.read_text(encoding="utf-8"))
        changed["tree"]["Workspace"]["APM_DistributionKits"]["APM_Kit"]["Installer"]["$properties"]["Enabled"] = True
        path.write_bytes(build.json_bytes(changed))
        before = path.read_bytes()
        with self.assertRaisesRegex(build.ExportError, "differs from manifest"):
            build.run(self.root, check=True)
        self.assertEqual(path.read_bytes(), before)

    def test_hash_detects_even_newline_changes(self) -> None:
        (self.root / "src/APM_Kit/Assistant.luau").write_bytes(self.source.replace(b"\r\n", b"\n"))
        with self.assertRaisesRegex(build.ExportError, "SHA256 mismatch"):
            build.expected_project(self.root)

    def test_unindexed_files_are_rejected(self) -> None:
        (self.root / "src/OldPreview.luau").write_bytes(b"return {}\n")
        with self.assertRaisesRegex(build.ExportError, "absent from manifest"):
            build.expected_project(self.root)

    def test_duplicate_instances_and_missing_parents_are_rejected(self) -> None:
        self.manifest["nodes"].append(copy.deepcopy(self.manifest["nodes"][0]))
        self.save()
        with self.assertRaisesRegex(build.ExportError, "Duplicate instance"):
            build.expected_project(self.root)
        self.manifest["nodes"].pop()
        self.manifest["nodes"][2]["path"] = ["Missing", "Parser"]
        self.save()
        with self.assertRaisesRegex(build.ExportError, "Missing parent"):
            build.expected_project(self.root)

    def test_path_traversal_is_rejected(self) -> None:
        self.manifest["nodes"][1]["sourceFile"] = "src/APM_Kit/../../outside.luau"
        self.save()
        with self.assertRaisesRegex(build.ExportError, "Invalid sourceFile"):
            build.expected_project(self.root)

    def test_missing_captured_properties_are_rejected(self) -> None:
        del self.manifest["nodes"][0]["archivable"]
        self.save()
        with self.assertRaisesRegex(build.ExportError, "archivable"):
            build.expected_project(self.root)


if __name__ == "__main__":
    unittest.main()
