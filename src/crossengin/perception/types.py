"""Typed perception data structures.

Per ADR-0004, perception observations carry their raw content plus
their embedding in the shared SigLIP space (768-dim float32, L2-normalized).
These types are frozen dataclasses; downstream modules treat them as
immutable values. Pydantic models will be introduced at the API boundary
in a later milestone.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

import numpy as np
from numpy.typing import NDArray

Modality = Literal["text", "image", "audio", "video"]

Embedding = NDArray[np.float32]


@dataclass(frozen=True, slots=True)
class RawObservation:
    """A perception input before encoding."""

    timestamp: float
    session_id: str
    modality: Modality
    content: str | bytes


@dataclass(frozen=True, slots=True)
class EncodedObservation:
    """A perception input with its embedding."""

    raw: RawObservation
    embedding: Embedding
    encoder_id: str
