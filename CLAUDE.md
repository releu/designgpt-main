# Design-GPT — Monorepo Project Guide

AI-assisted design generation tool. Users enter a prompt, the backend generates JSX code via AI, and a live preview renders it in an iframe using imported Figma component library components.

## Monorepo Layout

```
app/        Vue 3 (Options API) + Vite 7 frontend        → port 5173
api/        Rails 8 API-only + PostgreSQL backend         → port 3000
caddy/      Caddy reverse proxy (HTTPS, route splitting)  → port 443
e2e/        Playwright integration tests
```

Each subdirectory has its own git repo. There is no top-level git repo.
See `app/CLAUDE.md` and `api/CLAUDE.md` for detailed per-project guides.

## How Services Connect

Caddy is the single entry point in development:
- `https://design-gpt.localtest.me` — main app

Caddy routes `/api/*` → Rails on port 3000, everything else → Vite on port 5173.
Component preview rendering is handled by the API's `renderer` endpoint (loaded in iframe).
The `.localtest.me` domain resolves to `127.0.0.1` publicly — no `/etc/hosts` needed.
Caddy uses `tls internal` (self-signed certs).

## Starting Development

```sh
# All at once:
make dev

# Or individually:
cd api && bin/rails server      # Terminal 1: Rails API
cd app && npm run dev            # Terminal 2: Vite frontend
cd caddy && caddy run --config Caddyfile  # Terminal 3: Caddy proxy

# Then visit https://design-gpt.localtest.me
```

## Testing Infrastructure

Three test layers, run individually or together:

```sh
make test-app    # Frontend unit tests (Vitest + vue-test-utils + happy-dom)
make test-api    # API tests (RSpec: models, requests, services)
make test-e2e    # E2E integration tests (Playwright — starts all 3 servers)
make test        # Runs test-api + test-app (fast, no servers needed)
```

### Frontend Tests (app/)
- **Framework**: Vitest + @vue/test-utils + happy-dom
- **Config**: `app/vitest.config.js`
- **Convention**: Co-located `*.spec.js` files next to components
- **Auth mock**: Global mock in `app/src/__tests__/setup.js` — all tests get a mock `$auth0`
- **Run**: `cd app && npm test` or `npm run test:watch`

### API Tests (api/)
- **Framework**: RSpec
- **Fixtures**: `api/test/fixtures/*.yml` (no FactoryBot). Access as `users(:alice)`, `projects(:alice_project)`
- **Auth stubbing**: `stub_auth_for(user)` + `auth_headers(user)` from `spec/support/auth_helper.rb`
- **Run**: `cd api && bundle exec rspec`

### E2E Tests (e2e/)
- **Framework**: Playwright (Chromium)
- **Config**: `e2e/playwright.config.js` — starts Rails, Vite, and Caddy via `webServer` array
- **Auth mock**: API accepts HMAC test tokens when `E2E_TEST_MODE=true`. Frontend uses mock Auth0 plugin when `VITE_E2E_TEST=true`
- **DB setup**: `e2e/global-setup.js` runs `rails e2e:setup` — loads **only the `users` fixture** (alice). Everything else is created through the UI during the test session.
- **Real Figma API**: Integration tests make real calls to Figma. Requires `FIGMA_ACCESS_TOKEN` in `api/.env`. No sync bypass — the full import pipeline runs.
- **No pre-loaded data**: Tests start with a clean DB (user only) and drive the app the same way a real user would. Do not pre-load library or component fixtures for E2E tests.
- **Run**: `make test-e2e` or `cd e2e && npx playwright test`
- **No API mocks**: E2E tests make real API calls — never use `page.route()` to stub endpoints. Only auth is mocked.
- **Console errors**: Every test must track and assert zero console errors via `trackConsoleErrors(page)`.
- **Long-running tests**: Tests that include a real Figma sync must call `test.setTimeout(600_000)` (10 min). Use generous `toBeVisible` timeouts for the browser phase.

## Authentication Architecture

- **Frontend**: `@auth0/auth0-vue` plugin. Conditional in `app/src/main.js` — uses mock plugin when `VITE_E2E_TEST=true`
- **API**: `Auth0Service.decode_token` decodes JWT via JWKS (RS256). In E2E test mode (`E2E_TEST_MODE=true`), accepts HMAC tokens (HS256) signed with `e2e-test-secret-key`
- **Test user**: `auth0|alice123` / `alice@example.com` — matches `api/test/fixtures/users.yml`

## Known Issues

- **visual_diff_spec failures**: 2 expected failures in `spec/services/figma/visual_diff_spec.rb` (nil `diff_percent`) — separate task to address
- **ChatMessage model**: No `belongs_to :design` declared — use `design_id` column directly in fixtures
- **Art director disabled**: `ScreenshotJob` no longer triggers `analyze_last_render` — art director flow is commented out pending re-enablement
- **DesignSystem model**: Designs link to a `DesignSystem` (not directly to libraries). `is_root` / `allowed_children` now live in `DesignSystemComponentConfig` — see `api/CLAUDE.md`

## Figma Component Authoring Conventions

Special node-name conventions in Figma that affect code generation:

- **`@slot`** — An INSTANCE node whose name starts with `@slot` (e.g. `@slot`, `@slot content`). Marks the position where `{props.children}` is rendered in the generated React component. When present, `children` is added to the JSON schema as a required string. When absent, `children` is omitted entirely from the schema.
- **`@name`** — A TEXT node named with a `@` prefix (e.g. `@title`, `@description`). Becomes a required string prop in both the generated React code and the AI JSON schema. The AI fills it with content rather than passing JSX children. The `characters` value of the TEXT node becomes the default value. Example: a TEXT node named `@title` produces a `title` string prop — the JSX renders `{title}` instead of static text.
- **Duplicate `@name` validation** — If two TEXT nodes within the same component share the same `@name` (e.g. two nodes named `@title`), the component is skipped on import with a log warning (`SKIP <name>: duplicate @name text nodes: @title`). For `reimport_component` / `reimport_component_set`, an error is raised.

## Maintenance Rules

**These rules apply to every change made in this project:**

1. **Keep tests up to date**: When adding or modifying functionality, write or update corresponding tests in the appropriate layer (Vitest for frontend, RSpec for API). Run `make test` before considering work done.
2. **Keep CLAUDE.md files current**: When project structure, conventions, or architecture change, update the relevant CLAUDE.md file (this file, `app/CLAUDE.md`, or `api/CLAUDE.md`).
3. **Follow existing patterns**: Match the code style and testing conventions already established in each subdirectory. See the per-project CLAUDE.md files for details.
4. **E2E approach — real life, no shortcuts**: E2E tests must never mock API responses (`page.route()`). Only auth is mocked. Tests start with a clean DB (user only) and create all data through the UI. The full Figma sync pipeline runs — no bypasses. Write tests that expose bugs first (they should fail), fix the code, then confirm tests pass.
