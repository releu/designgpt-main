# Design-GPT — Project Guide

AI-assisted design generation tool. Users enter a prompt, the backend generates JSX code via AI, and a live preview renders it in an iframe using imported Figma component library components.

## Monorepo Layout

```
app/        Vue 3 (Options API) + Vite 7 frontend        → port 5173
api/        Rails 8 API-only + PostgreSQL backend         → port 3000
caddy/      Caddy reverse proxy (HTTPS, route splitting)  → port 443
e2e/        Playwright integration tests
```

Caddy is the single entry point: `https://design-gpt.localtest.me`
Routes `/api/*` → Rails, everything else → Vite.
`.localtest.me` resolves to `127.0.0.1` publicly. Caddy uses `tls internal` (self-signed).

## Starting Development

```sh
make dev                                       # All at once
cd api && bin/rails server                     # Terminal 1
cd app && npm run dev                          # Terminal 2
cd caddy && caddy run --config Caddyfile       # Terminal 3
```

---

## Frontend (app/)

### Tech Stack

- Vue 3 (Options API) + Vue Router 4 (history mode) + Vite 7
- JavaScript — no TypeScript
- SCSS (`lang="scss"` in all SFCs)
- Auth0 (`@auth0/auth0-vue`) + CodeMirror 6 (`vue-codemirror`)
- No state management library — components use `data()` + direct API calls

### Structure

```
src/
├── main.js              # Entry, global component registration, Auth0 + router
├── App.vue              # Root, Auth0 gate
├── assets/main.css      # Global CSS variables, @font-face
├── components/          # Auto-registered globally via import.meta.glob
├── router/index.js      # Routes: /, /designs/:id, /onboarding, /libraries, /libraries/:id
└── views/               # HomeView, OnboardingView, LibrariesView, LibraryDetailView
```

### Naming Conventions

| What | Convention | Examples |
|------|-----------|---------|
| Component files | PascalCase | `CodeField.vue`, `SectionHeader.vue` |
| CSS classes | BEM (PascalCase block) | `.MainLayout__prompt`, `.Preview_mobile` |
| BEM element / modifier | `__kebab` / `_kebab` | `__top-bar`, `_active` |
| JS variables / methods | camelCase | `selectedDesignId`, `generateView()` |
| CSS variables | `--kebab-case` | `--font-text-m`, `--orange` |

### Code Style

- **Options API** everywhere — `setup()` only for Auth0 composable
- Component order: `<template>`, `<script>`, `<style lang="scss">`
- **Views** (`src/views/`) are pure composition — no `<style>` section
- **Components** (`src/components/`) own all styles; BEM block = component name
- Layout structure in layout components (e.g. `MainLayout.vue`), not in views
- SCSS nesting via `&`: `&__element`, `&_modifier`
- Global tokens in `src/assets/main.css` (`:root` CSS variables)
- Font: Suisse Intl (`"suiss"` family). Border-radius: 24px cards, 32px buttons, 60px mobile

---

## API (api/)

### Tech Stack

- Rails 8.0.2 (API-only), Ruby 3.3.9, PostgreSQL
- Puma, Solid Queue / Cache / Cable
- Auth0 + JWT, RSpec, WebMock
- DB names: `jan_designer_api_development` / `jan_designer_api_test`

### Structure

```
app/
├── controllers/           # All scoped under /api
├── models/                # Domain models + DesignGenerator, ArtDirector
├── services/              # Plain Ruby — Figma pipeline, exports, auth
│   └── figma/             # Client → Importer → ReactFactory → VisualDiff
└── jobs/                  # AiRequestJob, ScreenshotJob, ComponentLibrarySyncJob
```

### Key Domain Relationships

```
User → DesignSystems → DesignSystemLibraries → ComponentLibraries → Components
                                                                   → ComponentSets → ComponentVariants
                                                                   → FigmaAssets
User → Designs → Iterations (JSX snapshots)
               → ChatMessages
               → DesignComponentLibraries → ComponentLibraries
```

### Design Status Flow

`draft → generating → ready | error`

### API Routes

All scoped under `/api`:

| Method | Path | Action |
|--------|------|--------|
| GET | /api/design-systems | List user's design systems |
| POST | /api/design-systems | Create (name + component_library_ids) |
| GET | /api/component-libraries | List own libraries |
| GET | /api/component-libraries/available | Own + public libs |
| POST | /api/component-libraries | Create (import from Figma) |
| GET | /api/component-libraries/:id | Show with components |
| GET | /api/component-libraries/:id/renderer | Iframe renderer (no auth) |
| PATCH | /api/component-libraries/:id | Update name, is_public |
| POST | /api/component-libraries/:id/sync | Re-sync from Figma (async) |
| GET | /api/component-libraries/:id/components | List components |
| PATCH | /api/component-sets/:id | Update is_root, allowed_children |
| POST | /api/components/:id/reimport | Re-import single component |
| POST | /api/component-sets/:id/reimport | Re-import single component set |
| GET | /api/components/:id/visual_diff | Visual diff results |
| GET | /api/designs | List user's designs |
| POST | /api/designs | Create (prompt + design_system_id or component_library_ids) |
| GET | /api/designs/:id | Show design + iterations |
| PATCH | /api/designs/:id | Update design name |
| DELETE | /api/designs/:id | Delete design |
| POST | /api/designs/:id/improve | Iterate on design (chat) |
| POST | /api/designs/:id/duplicate | Duplicate design |
| GET | /api/designs/:id/export_image | Export as PNG |
| GET | /api/designs/:id/export_react | Export as React project zip |
| GET | /api/designs/:id/export_figma | Export tree JSON for Figma |
| POST | /api/custom-components | Upload custom React component |
| GET | /api/up | Health check |

### Controller Style

- Inherit `ApplicationController` (extends `ActionController::API`)
- `rescue_from RecordNotFound` → 404
- `before_action :require_auth` for protected endpoints
- `current_user` decodes JWT via `Auth0Service.decode_token`, auto-creates User on first login
- Render JSON inline — no serializers. Use bang methods (`create!`, `update!`)
- Strong params via private `*_params` methods
- Read access: `accessible_*` / `find_accessible_*`. Write: `find_user_*` / `find_owned_*`

### Model Style

- Standard Rails conventions. Business logic in models (`Design#generate`, `Design#improve`)
- AI orchestration in `DesignGenerator` and `ArtDirector`
- No callbacks for complex logic — explicit method calls

### Service Style

- Plain Ruby under `app/services/`. Figma pipeline: `Client → Importer → ReactFactory / StyleExtractor → VisualDiff`
- Sync statuses: pending → discovering → importing → converting → comparing → ready | error
- `ComponentLibrarySyncJob` wraps `sync_with_figma` for async execution

---

## Authentication

- **Frontend**: `@auth0/auth0-vue`. Mock plugin when `VITE_E2E_TEST=true`
- **API**: `Auth0Service.decode_token` decodes JWT (RS256 via JWKS). E2E mode (`E2E_TEST_MODE=true`) accepts HMAC tokens (HS256) signed with `e2e-test-secret-key`
- **Test user**: `auth0|alice123` / `alice@example.com`

---

## Testing

### Frontend Tests (app/)

- **Framework**: Vitest + @vue/test-utils + happy-dom
- **Config**: `app/vitest.config.js`
- **Convention**: Co-located `*.spec.js` next to components
- **Auth mock**: Global mock in `app/src/__tests__/setup.js`
- **Run**: `cd app && npm test`

### API Tests (api/)

- **Framework**: RSpec
- **Fixtures**: `api/test/fixtures/*.yml` (no FactoryBot). Access as `users(:alice)`, `designs(:alice_design)`
- **Auth**: `stub_auth_for(user)` + `auth_headers(user)` from `spec/support/auth_helper.rb`
- **HTTP stubbing**: WebMock for external API calls
- **Run**: `cd api && bundle exec rspec`

### E2E Tests (e2e/)

- **Framework**: Playwright + playwright-bdd (Gherkin BDD)
- **Base URL**: `https://design-gpt.localtest.me`
- **Config**: `e2e/playwright.config.js` — uses `defineBddConfig()`, starts Rails, Vite, Caddy via `webServer`
- **DB setup**: `e2e/global-setup.js` runs `rails db:test:prepare` + `rails e2e:setup` (loads only `users` fixture)
- **Auth**: HMAC test tokens, auto-logged in as alice
- **Real Figma API**: Requires `FIGMA_ACCESS_TOKEN` in `api/.env`. Full sync pipeline, no bypass.
- **Run**: `make test-e2e` or `cd e2e && npm test`

**E2E structure:**
```
e2e/
  fixtures/test.js           # Custom fixture: consoleErrors (auto), world (shared state)
  features/*.feature         # Gherkin feature files
  steps/*.steps.js           # Step definitions (use createBdd from playwright-bdd)
  .features-gen/             # Auto-generated by bddgen (gitignored)
```

**E2E conventions:**
- Never mock API responses (`page.route()`). Only auth is mocked.
- Console error tracking via `consoleErrors` fixture (auto-attached). Assert with `expect(consoleErrors).toEqual([])`.
- Tests with real Figma sync: `@timeout:600000` tag. Generous `toBeVisible` timeouts (up to 300s).
- No pre-loaded data — tests create everything through the UI.
- Step definitions use `createBdd(test)` from the custom fixture.

### E2E Test Catalog

#### `features/health.feature` — Health Check

```gherkin
Feature: Health Check

  Scenario: API health endpoint responds
    When I send a GET request to "/api/up"
    Then the response status should be OK

  Scenario: Frontend loads
    When I navigate to the home page
    Then the app container should be visible
```

#### `features/design-workflow.feature` — Design Workflow

Serial scenarios — Scenario 2 depends on state created by Scenario 1.

```gherkin
@mode:serial
@timeout:600000
Feature: Design Workflow

  Scenario: Import Figma file and create a design system
    Given I navigate to the home page
    And the app container is visible
    When I click "New design system"
    Then the design system modal should be visible
    When I add a Figma URL "<figma-url>"
    Then the Figma URL should appear in the pending list
    When I click "Import"
    Then the component browser should be visible within 5 minutes
    When I enter the design system name "Example"
    And I click "Page" in the component browser menu
    And I check the "Root component" checkbox
    And I add "Title" as an allowed child
    Then "Title" should appear in the allowed children list
    When I add "Text" as an allowed child
    Then "Text" should appear in the allowed children list
    When I click "Save"
    Then the design system modal should close
    And a design system should appear in the library selector
    And there are no console errors

  Scenario: Generate a design from a prompt
    Given I navigate to the home page
    And I had a previously added design system "Example"
    When I set the prompt to "List top places in Belgrade"
    And I select the design system "Example"
    And I click "Generate"
    Then I should be navigated to a design page
    And I should see the design page layout with chat and preview
    And the preview should show the empty state
    When I wait for the design generation to complete
    Then the preview should display the generated design
    And there are no console errors
```

### Running All Tests

```sh
make test        # API + frontend (fast, no servers)
make test-api    # API only
make test-app    # Frontend only
make test-e2e    # E2E (starts servers, real Figma calls)
```

### Known Test Failures

- `spec/services/figma/visual_diff_spec.rb` — 2 failures (nil `diff_percent`). Known, separate task.

---

## Known Issues

- **ChatMessage model**: No `belongs_to :design` declared — use `design_id` column directly
- **Art director disabled**: `ScreenshotJob` no longer triggers `analyze_last_render` — commented out pending re-enablement

## Maintenance Rules

1. **Keep tests up to date**: Write or update tests when changing functionality. Run `make test` before done.
2. **Keep this CLAUDE.md current**: Update when structure, conventions, or architecture change.
3. **Follow existing patterns**: Match code style and testing conventions in each subdirectory.
4. **E2E — no shortcuts**: No API mocks. Clean DB. Data through UI. Full Figma pipeline. Write failing tests first, then fix.
