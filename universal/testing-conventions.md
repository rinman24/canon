---
module: testing-conventions
tier: universal
summary: Fixtures-over-inline-classes, declare-conftest-fixtures comment, conftest placement scoping, fixture naming prefixes (noop/spy/fake/capturing/make/default), factory-fixture pattern, explicit fixture-param typing.
requires: []
---

# Testing Conventions

**Fixtures over inline classes** — All arrange-step helper classes (stubs, fakes, spies) must be pytest fixtures. Never define the same helper class in more than one test file.

**Declaring conftest fixtures in test files** — Every test file that uses fixtures defined in a `conftest.py` must include a comment immediately after the imports listing those fixture names and the conftest path:
```python
# noop_uow, noop_clock, fake_order_access
# are provided by tests/unit/orders/conftest.py
```
This makes the implicit pytest dependency explicit and searchable without opening conftest.

**conftest.py placement:**

| Scope | File |
|---|---|
| Shared across a subsystem's unit tests | `tests/unit/<subsystem>/conftest.py` |
| Shared across all unit tests | `tests/unit/conftest.py` |
| Integration-specific | `tests/integration/conftest.py` |

**Fixture naming conventions:**

| Prefix | Meaning |
|---|---|
| `noop_*` | Silent stub; ignores all inputs |
| `spy_*` | Records calls for later assertion |
| `fake_*` | Configurable in-memory replacement |
| `capturing_*` | Records last interaction for assertion |
| `make_*` | Factory fixture — call with kwargs to produce the object |
| `default_*` | Stable, reusable test data instance |

**Factory fixtures** — For parameterized helpers, return a callable from the fixture:
```python
@pytest.fixture
def make_fake_order_access(spy_uow, default_order_row):
    def _factory(**kwargs):
        return _FakeOrderAccess(session=spy_uow.session, order=kwargs.pop("order", default_order_row), **kwargs)
    return _factory
```

**Typing fixture parameters** — Pyright cannot infer fixture parameter types from conftest return annotations; every fixture parameter must be explicitly typed.

- Use the public Protocol type when one exists.
- For conftest stubs that only expose part of an interface (e.g. a UoW stub exposing only `.session`), define a minimal local Protocol rather than importing the private conftest class:
  ```python
  class _HasSession(Protocol):
      session: object
  ```
- Give factory fixtures an explicit return type and annotate test-function parameters to match:
  ```python
  @pytest.fixture
  def make_flow(
      noop_uow: _HasSession,
      noop_notifier: Notifier,
      accepting_policy_engine: object,  # passed via type: ignore[arg-type]
  ) -> Callable[..., CheckoutFlow]:
      ...

  async def test_something(make_flow: Callable[..., CheckoutFlow]) -> None:
      flow = make_flow(...)  # Pyright now knows flow: CheckoutFlow
  ```
