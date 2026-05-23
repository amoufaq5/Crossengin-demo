"""Shared fixtures for perception tests."""

from __future__ import annotations

import pytest

from crossengin.perception import (
    FakeTextEncoder,
    StreamingBuffer,
    TextPerceptionPipeline,
)


@pytest.fixture
def fake_encoder() -> FakeTextEncoder:
    return FakeTextEncoder()


@pytest.fixture
def small_buffer() -> StreamingBuffer:
    return StreamingBuffer(max_items=4, max_age_seconds=60.0)


@pytest.fixture
def fake_pipeline(
    fake_encoder: FakeTextEncoder,
    small_buffer: StreamingBuffer,
) -> TextPerceptionPipeline:
    return TextPerceptionPipeline(encoder=fake_encoder, buffer=small_buffer)
