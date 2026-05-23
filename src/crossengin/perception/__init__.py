"""Multimodal perception module.

At M2 only text is implemented. Image support arrives in a later
milestone per ADR-0004.

See ADR-0004 for the architectural spec and ADR-0022 for the milestone
plan.
"""

from crossengin.perception.buffer import StreamingBuffer
from crossengin.perception.encoders import (
    FakeTextEncoder,
    SigLIPTextEncoder,
    TextEncoder,
)
from crossengin.perception.pipeline import TextPerceptionPipeline
from crossengin.perception.types import (
    Embedding,
    EncodedObservation,
    Modality,
    RawObservation,
)

__all__ = [
    "Embedding",
    "EncodedObservation",
    "FakeTextEncoder",
    "Modality",
    "RawObservation",
    "SigLIPTextEncoder",
    "StreamingBuffer",
    "TextEncoder",
    "TextPerceptionPipeline",
]
