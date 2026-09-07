import json
import sys
import shutil
from pathlib import Path

def mutate(lifecycle_path: Path, source_path: Path, case_name: str):
    # Reset from source
    shutil.copy(source_path, lifecycle_path)
    
    with open(lifecycle_path) as f:
        d = json.load(f)
    
    if case_name == "invalid_stage":
        d["stages"][0]["stage"] = "bogus_stage"
    elif case_name == "duplicate_label":
        d["stages"][0]["stage"] = "plan"
        d["stages"][1]["label"] = d["stages"][0]["label"]
    elif case_name == "missing_advances_on":
        d["stages"][1]["label"] = "status:spec"
        del d["stages"][0]["advances_on"]
    elif case_name == "invalid_advances_on":
        d["stages"][0]["advances_on"] = "invalid_trigger"
    elif case_name == "artifact_mismatch_null":
        d["stages"][0]["advances_on"] = "artifact"
        d["stages"][0]["artifact"] = None
    elif case_name == "artifact_mismatch_non_null":
        d["stages"][0]["artifact"] = "intent.md"
        d["stages"][3]["artifact"] = "unexpected.md"
    elif case_name == "advances_on_non_terminal_null":
        d["stages"][3]["artifact"] = None
        d["stages"][0]["advances_on"] = None
        d["stages"][0]["artifact"] = None
    elif case_name == "advances_on_terminal_not_null":
        d["stages"][0]["advances_on"] = "artifact"
        d["stages"][0]["artifact"] = "intent.md"
        d["stages"][4]["advances_on"] = "merge"
    elif case_name == "advances_to_non_terminal_null":
        d["stages"][4]["advances_on"] = None
        d["stages"][0]["advances_to"] = None
    elif case_name == "advances_to_terminal_not_null":
        d["stages"][0]["advances_to"] = "status:spec"
        d["stages"][4]["advances_to"] = "status:done"
    elif case_name == "multiple_merges":
        d["stages"][4]["advances_to"] = None
        d["stages"][0]["advances_on"] = "merge"
        d["stages"][0]["artifact"] = None
    elif case_name == "zero_merges":
        d["stages"][0]["advances_on"] = "artifact"
        d["stages"][0]["artifact"] = "intent.md"
        d["stages"][3]["advances_on"] = "artifact"
        d["stages"][3]["artifact"] = "code.patch"
    else:
        sys.exit(f"Unknown case: {case_name}")

    with open(lifecycle_path, "w") as f:
        json.dump(d, f)

if __name__ == "__main__":
    mutate(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3])
