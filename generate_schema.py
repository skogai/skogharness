# /// script
# dependencies = ["pydantic"]
# ///
"""Generate JSON Schema files from the placeholder models in test_schemas.py.

Run with: uv run generate_schema.py
"""

import json
from pathlib import Path

from test_schemas import TestDocument

OUT_DIR = Path(__file__).parent / "generated-schemas"

MODELS = {
    "TestDocument": TestDocument,
}


def main() -> None:
    OUT_DIR.mkdir(exist_ok=True)
    for name, model in MODELS.items():
        schema = model.model_json_schema()
        out_path = OUT_DIR / f"{name}.schema.json"
        out_path.write_text(json.dumps(schema, indent=2) + "\n")
        print(f"wrote {out_path}")


if __name__ == "__main__":
    main()
