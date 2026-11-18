---
paths:
  - "src/api/**/*.py"
  - "src/models/**/*.py"
---
- Dependency flow is `api/` (routers → services) → `models/`, never reversed.
- Routers stay thin: accept the body, call the service, return the result.
- Schemas extend `BaseSchema` (camelCase aliases); map exceptions to HTTP responses only in `error_handler.py`.
