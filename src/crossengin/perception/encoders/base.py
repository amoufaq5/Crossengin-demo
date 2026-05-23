"""Abstract encoder interface.

All text encoders implement TextEncoder. SigLIPTextEncoder is the v0
default; FakeTextEncoder exists for fast deterministic unit tests.
"""

from __future__ import annotations

from abc import ABC, abstractmethod

import numpy as np

from crossengin.perception.types import Embedding


class TextEncoder(ABC):
    """An encoder that maps text strings to fixed-dimension embeddings."""

    @property
    @abstractmethod
    def encoder_id(self) -> str:
        """A stable identifier for provenance, e.g. the HF model name."""

    @property
    @abstractmethod
    def embedding_dim(self) -> int:
        """The dimension D of the embedding space this encoder produces."""

    @abstractmethod
    def encode(self, texts: list[str]) -> Embedding:
        """Encode a batch of texts.

        Returns an ndarray of shape (len(texts), embedding_dim), dtype
        float32, L2-normalized along the last axis.
        """

    def encode_one(self, text: str) -> Embedding:
        """Encode a single text. Returns shape (embedding_dim,)."""
        batch = self.encode([text])
        return np.asarray(batch[0], dtype=np.float32)
