---
module: architecture-closed
tier: universal
summary: Löwy closed architecture — volatility decomposition, Manager/Engine/Access layering, closed subsystems, contract-driven DTOs, code-gen order, anti-patterns.
requires: []
---

# Project Architecture: Closed Architecture (Juval Löwy / Righting Software)

This project follows Juval Löwy's closed architecture principles from "Righting Software."

## Core Principles

1. **Volatility-based decomposition** - Decompose by what's likely to change, not by function
2. **Closed subsystems** - Each subsystem has a single Manager entry point; internals are hidden
3. **No bypass** - External code never reaches Engine or Access directly; everything flows through Managers
4. **Minimal public surface** - Managers expose only externally-required operations, nothing more
5. **Contract-driven** - Layers communicate via well-defined contracts/interfaces

## Layer Structure

```
┌─────────────────────────────────────────────────────────────┐
│  API Layer                                                  │
│  - Routers, dependencies, request/response schemas          │
│  - Calls Managers only                                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Manager Layer (one Manager per subsystem)                  │
│                                                             │
│  Responsibilities:                                          │
│  - Single entry point per subsystem                         │
│  - One public method per use case                           │
│  - Orchestrates Engine calls                                │
│  - Manages transactions via Unit of Work                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Engine Layer                                               │
│                                                             │
│  Responsibilities:                                          │
│  - Business logic, rules, algorithms                        │
│  - Domain decisions                                         │
│  - No direct infrastructure dependencies                    │
│  - Receives Access layer via constructor/DI                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Access Layer                                               │
│                                                             │
│  Responsibilities:                                          │
│  - Data persistence                                         │
│  - External service integration                             │
│  - Returns domain-oriented data structures, not ORM models  │
└─────────────────────────────────────────────────────────────┘
```

## Subsystem Organization

Each subsystem follows this structure:

```
<root_pkg>/<subsystem>/
├── contracts/       # Public interfaces and DTOs for the subsystem
├── domain/          # Domain objects, commands, results
├── engine/          # Business logic (one or more engines)
└── manager/         # Single Manager class (subsystem entry point)
```

## Key Rules

### Manager Rules
- One Manager per subsystem
- One public method per externally-required operation
- No helper methods exposed publicly
- No Access layer methods exposed directly
- Manages Unit of Work lifecycle (transaction boundaries)

### Engine Rules
- Contains business logic and domain rules
- Framework-agnostic (no web framework imports, no direct ORM)
- Receives Access classes via dependency injection
- Multiple engines per subsystem allowed if cohesive

### Access Rules
- One Access class per aggregate/entity
- Methods return domain objects (dataclasses), not ORM models
- Contracts define specs (CreateXxxSpec, XxxRow, UpdateXxxSpec)
- ORM/driver error handling belongs here

### Contract Patterns
- `CreateXxxSpec` - Input for creating an entity
- `XxxRow` - Read result from database
- `UpdateXxxSpec` - Input for updating an entity
- Use `@dataclass(frozen=True, slots=True)` for immutability

## Code Generation Guidelines

When generating new code:

1. **Respect layer boundaries** - Never let API call Access directly
2. **Start at the contract** - Define the Manager's public method signature first
3. **Work downward** - Manager → Engine → Access
4. **Use dependency injection** - Pass Access to Engine, Engine to Manager
5. **Frozen dataclasses** - Use `@dataclass(frozen=True, slots=True)` for contracts
6. **Unit of Work** - Managers control transaction boundaries
7. **No leaky abstractions** - Access returns domain objects, not ORM models

### Adding a New Feature

1. Define the Manager method signature (the use case)
2. Create domain objects in `<subsystem>/domain/`
3. Implement Engine logic
4. Implement Access methods if new data access needed
5. Wire up in Manager
6. Add API route that calls Manager
7. Write tests at each layer

### Naming Conventions

| File | Purpose |
|------|---------|
| `*_manager.py` | Subsystem entry point |
| `*_engine.py` | Business logic |
| `*_access.py` | Data/external access |
| `contracts.py` | Layer interfaces and DTOs |
| `domain/*.py` | Domain objects, commands, results |

## Anti-Patterns to Avoid

- Exposing Access methods through Manager without orchestration
- Calling Engine directly from API layer
- Returning ORM models from Access layer
- Multiple Managers for the same subsystem
- "Bag of functions" Managers with utility methods
- Deep call chains between services
