---
paths:
  - "src/components/ui/**"
  - "src/router.tsx"
  - "src/lib/constants/env.ts"
---
- `src/components/ui/` is shadcn, CLI-managed: add with `npx shadcn@latest add`, never edit by hand.
- Routes are defined in `src/router.tsx`, not by filesystem convention.
- Read env only through `src/lib/constants/env.ts`; `VITE_*` values are public.
