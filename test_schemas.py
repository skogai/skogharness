# /// script
# dependencies = ["pydantic"]
# ///
"""Placeholder Pydantic schemas for skogharness.

These are test/example shapes only -- NOT a verified port of the real
skogai-routing schemas (.old/schemas/*.json). That repo isn't reachable
from this session, so the real document types, section names, and enums
have not been confirmed against source. This file exists to prove the
Pydantic -> JSON Schema generation pipeline (generate_schema.py) works
end to end. Replace with real shapes once someone can read the actual
schema files.
"""

from enum import Enum

from pydantic import BaseModel, Field


class DocType(str, Enum):
    """Placeholder type values, not confirmed against defs.schema.json."""

    router = "router"
    workflow = "workflow"
    reference = "reference"


class TestSection(BaseModel):
    name: str
    content: str | None = None


class TestDocument(BaseModel):
    """A minimal stand-in document shape -- not the real skogai-routing document schema."""

    path: str
    type: DocType
    sections: list[TestSection] = Field(default_factory=list)
