Accessibility Requirements

- All generated UI code MUST adhere to WCAG 2.2 AA.
- Use semantic HTML elements for interactive controls.
- Provide full keyboard navigation and visible focus behavior.
- Include appropriate ARIA roles and labels only when necessary.
- Manage focus dynamically where required (for example dialogs, drawers, and async UI updates).
- Do not use non-semantic elements for interactive controls.
- Validate accessibility with automated checks when available and manual keyboard testing.

Preferred Ruby Method Parameters

- For new application code, prefer keyword arguments over positional arguments for methods that have optional behavior, multiple booleans, style options, or more than one non-obvious argument.
- Design call sites for readability and intent. Favor explicit names at the call site over argument order.
- Keep positional arguments only when the API is naturally positional and universally clear (for example simple arithmetic or very small internal utility methods).
- For public or widely-used methods, avoid breaking callers abruptly. Migrate in phases:
1. Add keyword-based API.
2. Update call sites.
3. Remove legacy positional form after adoption.
- For option-heavy methods, keep defaults in the method signature and avoid passing generic option hashes unless required for framework interoperability.
- When adding or changing methods, update existing call sites to match the keyword style in the same change when practical.

Enforcement

- Enforce what RuboCop can check in CI.
- Use this instruction file as the source of truth for conventions RuboCop cannot fully enforce.
- If a convention repeatedly slips through linting, consider adding a custom RuboCop rule.
