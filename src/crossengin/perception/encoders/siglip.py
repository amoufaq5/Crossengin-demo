"""SigLIP-base text encoder (Apache 2.0).

Wraps google/siglip-base-patch16-224 from HuggingFace. The model is
downloaded on first construction to the HuggingFace cache; subsequent
loads are fast. Inference runs under torch.no_grad on CPU at M2.

Uses AutoTokenizer rather than AutoProcessor: SigLIP's combined
processor pulls in PIL for image preprocessing, which is unnecessary
weight for M2's text-only path. Image support arrives in a later
milestone per ADR-0004 and will introduce the image side of the model.
"""

from __future__ import annotations

import numpy as np
import torch
from transformers import AutoModel, AutoTokenizer

from crossengin.perception.encoders.base import TextEncoder
from crossengin.perception.types import Embedding


class SigLIPTextEncoder(TextEncoder):
    """SigLIP-base text encoder."""

    MODEL_NAME = "google/siglip-base-patch16-224"
    EMBEDDING_DIM = 768

    def __init__(self, device: str = "cpu") -> None:
        self._device = device
        self._tokenizer = AutoTokenizer.from_pretrained(self.MODEL_NAME)  # type: ignore[no-untyped-call]
        self._model = AutoModel.from_pretrained(self.MODEL_NAME).to(device)
        self._model.eval()

    @property
    def encoder_id(self) -> str:
        return self.MODEL_NAME

    @property
    def embedding_dim(self) -> int:
        return self.EMBEDDING_DIM

    @torch.no_grad()
    def encode(self, texts: list[str]) -> Embedding:
        if not texts:
            return np.empty((0, self.embedding_dim), dtype=np.float32)
        inputs = self._tokenizer(
            texts,
            padding="max_length",
            truncation=True,
            return_tensors="pt",
        ).to(self._device)
        features = self._model.get_text_features(**inputs)
        features = features / features.norm(dim=-1, keepdim=True).clamp_min(1e-9)
        return np.asarray(features.cpu().numpy(), dtype=np.float32)
