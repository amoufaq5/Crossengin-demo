# Crossengin Demo

A privacy-first multimodal AI companion.

This repository is the implementation of the architecture documented in
[`docs/adr/`](docs/adr/). Start with
[ADR-0002](docs/adr/0002-project-scope-and-v0-mvp.md) for project scope and
[ADR-0022](docs/adr/0022-evaluation-and-milestone-plan.md) for the v0
evaluation criteria and milestone plan.

## Status

Repository scaffold. No functional code yet.

## Development

This project uses [uv](https://docs.astral.sh/uv/) for dependency management
and targets Python 3.12+.

```bash
# Install dependencies
uv sync --all-extras --dev

# Run the test suite
uv run pytest

# Run linter and formatter
uv run ruff check .
uv run ruff format .

# Run type checker
uv run mypy
```

## License

Apache License 2.0. See [LICENSE](LICENSE).
