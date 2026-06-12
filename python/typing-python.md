---
module: typing-python
tier: python
summary: Strong typing everywhere — pyright strict (0 errors), modern union/list/dict/tuple syntax, explicit param/return/local annotations, judicious `from __future__ import annotations`.
requires: []
---

# Type Hinting (Python)

This project uses **strong type hinting everywhere**. All code must be fully typed.

## Requirements

- **All function parameters** must have type hints
- **All return types** must be specified (including `-> None` for void functions)
- **All local variables** should have explicit type annotations
- Follow strict typing expectations (`pyright` strict mode). **Every file you touch must
  pass `pyright` with 0 errors before hand-off.**
- Only add `from __future__ import annotations` when it provides clear value (e.g.
  unavoidable forward references); prefer normal evaluated annotations otherwise.

## Style

```python
# Use modern union syntax (Python 3.10+)
def get_user(user_id: int) -> User | None:
    model: User | None = await self._session.get(User, user_id)
    return model

# Type hint local variables explicitly
async def insert(self, spec: CreateUserSpec) -> UserRow:
    model: User = spec.to_model()
    self._session.add(model)
    await self._session.flush()
    row: UserRow = UserRow.from_model(model)
    return row

# Use list[], dict[], tuple[] not List[], Dict[], Tuple[]
def get_errors(self, name: str) -> list[str]:
    errors: list[str] = []
    return errors
```

## Conventions

| Pattern | Example |
|---------|---------|
| Optional values | `X | None` (not `Optional[X]`) |
| Lists | `list[X]` (not `List[X]`) |
| Dicts | `dict[K, V]` (not `Dict[K, V]`) |
| Tuples | `tuple[X, Y]` (not `Tuple[X, Y]`) |
| Void returns | `-> None` (always explicit) |
