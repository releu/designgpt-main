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

### Writing Strong Tests

**Every assertion must verify the actual outcome, not a proxy for it.** A test that checks a container exists without checking its content is a weak test — it passes even when the feature is broken.

Rules:
- **Assert on content, not containers.** Don't just check that an element is visible — check that it contains the expected data. An empty iframe, an empty list, or a spinner that never resolves are all "visible" but broken.
- **Assert inside iframes.** Use `page.frameLocator()` to reach into iframe content. Checking iframe `src` or visibility proves nothing about what rendered inside.
- **Assert on user-visible text.** If the feature shows data to the user (names, numbers, messages), assert on that text. Use `toContainText`, `toHaveText`, or content checks — not `toBeVisible` alone.
- **Never treat "element exists" as "feature works."** A loading spinner, error message, or empty state are all existing elements. The test must distinguish success from these failure modes.
- **Test the specific outcome.** If the prompt is "rivers in Belgrade", assert the preview contains actual river names. If import creates components, assert the component names appear in the UI. Generic "something rendered" checks catch nothing.
- **Prefer `not.toBeEmpty()` over `toBeVisible()` for content areas.** An empty `#root` div is visible but useless.
- **Always end E2E scenarios with `And there are no console errors`.** Rendering failures, JS exceptions, and network errors all surface in the console.

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

## Design Generation Flow

1. **Import**: User provides Figma file URLs. The system imports all components from them (component sets with variants, standalone components, icons).
2. **Configure**: User sets `is_root` and `allowed_children` on components to define valid nesting structure. Creates a design system grouping the libraries.
3. **Prompt**: User writes a text prompt describing the desired design.
4. **Schema generation**: Backend builds a JSON Schema from the component library — component names, their props (extracted from variant names), `is_root` to identify top-level components, `allowed_children` to constrain valid nesting.
5. **AI request**: The prompt + JSON Schema are sent to the AI model. The schema is passed as the structured output format so the AI generates valid JSON matching the component tree structure.
6. **Transform**: The returned JSON tree is transformed into JSX code using the component names and props.
7. **Render**: The JSX is sent via `postMessage` to the renderer iframe — an HTML page with React, ReactDOM, Babel, and all the library's compiled React components pre-loaded. Babel compiles the JSX at runtime, and React renders it.
8. **Preview**: The rendered result appears in the preview iframe (mobile or desktop layout).

## Implementation Plan — Design Generation Flow

All 8 steps have existing code. The plan below verifies each step works, fixes integration issues, and adds missing tests. Each step is a standalone AI session.

### Current Implementation Status

| Step | Code exists | Key files |
|------|------------|-----------|
| 1. Import | ✅ | `figma/client.rb`, `figma/importer.rb`, `figma/asset_extractor.rb`, `ComponentLibrarySyncJob` |
| 2. Configure | ✅ | `DesignSystemModal.vue`, `ComponentSetsController`, `DesignSystem` model |
| 3. Prompt | ✅ | `Prompt.vue`, `HomeView.vue`, `DesignsController#create` |
| 4. Schema generation | ✅ | `DesignGenerator#build_schema`, `#build_defs`, `ComponentNaming` concern |
| 5. AI request | ✅ | `AiRequestJob`, `AiTask` model, OpenAI API (`gpt-5`, structured output) |
| 6. Transform | ✅ | `JsonToJsx` service, `AiTask#jsx` |
| 7. Render | ✅ | `Renderable` concern, renderer endpoints (no auth), React + Babel in HTML |
| 8. Preview | ✅ | `Preview.vue`, `DesignView.vue` (polling + postMessage) |

### Session 1 — Verify & fix Step 1 (Import)

**Goal**: Confirm the Figma import pipeline works end-to-end with a real Figma file.

- Run `make test-api` — check all import-related specs pass (`figma/importer_spec.rb`, `figma/client_spec.rb`, `figma/asset_extractor_spec.rb`, `component_library_sync_job_spec.rb`)
- Fix any failing tests
- Manually test: start dev servers, create a component library from a Figma URL, watch sync complete
- Verify: ComponentLibrary reaches `status: "ready"`, ComponentSets/Components/FigmaAssets are populated
- Check that `react_code` and `react_code_compiled` are generated for all components (ReactFactory output)
- Fix `visual_diff_spec.rb` known failures (2 tests with nil `diff_percent`) if straightforward

### Session 2 — Verify & fix Step 2 (Configure)

**Goal**: Confirm is_root/allowed_children configuration and design system creation work.

- Verify PATCH `/api/component-sets/:id` correctly saves `is_root` and `allowed_children`
- Verify POST `/api/design-systems` creates a design system with linked libraries
- Test the full DesignSystemModal.vue flow: import → browse components → set is_root → add allowed_children → save
- Run related specs (`component_sets_controller_spec.rb`, `design_systems_controller_spec.rb`)
- Verify `allowed_children` stores component names that actually exist in the library
- Ensure the saved design system appears in the home page library selector

### Session 3 — Verify & fix Step 4 (Schema Generation)

**Goal**: Confirm the JSON Schema built from component libraries is valid and complete.

- Write/run a test that creates a ComponentLibrary with known ComponentSets + Components, then calls `DesignGenerator#build_schema` and validates the output
- Verify: root components appear in `AllComponents` anyOf, props extracted correctly (VARIANT → enum, TEXT → string, BOOLEAN → boolean), `allowed_children` constrains children refs
- Check edge cases: icons excluded from schema, components with no variants, components with no children
- Validate the schema is valid JSON Schema (can be parsed by a JSON Schema validator)
- Add spec coverage for `DesignGenerator` if missing

### Session 4 — Verify & fix Step 5 (AI Request)

**Goal**: Confirm the AI request job sends a valid payload and handles the response correctly.

- Verify `OPENAI_API_KEY` is configured in `api/.env`
- Review `AiRequestJob` payload structure — confirm it matches OpenAI's `/v1/responses` API format
- Write/run spec with WebMock: stub OpenAI API, verify request payload shape, verify response parsing
- Test `AiTask#args` correctly extracts the JSON tree from the response
- Test error handling: what happens when OpenAI returns an error, rate limit, or malformed response
- Verify Design status transitions: `draft → generating → ready` on success, `→ error` on failure

### Session 5 — Verify & fix Step 6 (Transform: JSON → JSX)

**Goal**: Confirm JsonToJsx produces correct JSX from AI-generated JSON trees.

- Run existing `JsonToJsx` specs if any; add specs if missing
- Test with realistic component trees: nested components, string children, boolean props, enum props
- Verify prop serialization: strings quoted, booleans as `{true}`, numbers as `{42}`, arrays/objects as JSON
- Test edge cases: empty children, null values, deeply nested trees, special characters in text
- Verify the JSX output is valid (can be compiled by Babel without errors)

### Session 6 — Verify & fix Steps 7-8 (Render & Preview)

**Goal**: Confirm the renderer iframe loads components and renders JSX correctly.

- Start dev servers, open a renderer URL in browser (`/api/component-libraries/:id/renderer`)
- Verify: React, ReactDOM, Babel loaded; component code injected; `postMessage` listener active
- Test from browser console: `postMessage({ type: "render", jsx: "<Button>Test</Button>" }, "*")` — verify it renders
- Verify Preview.vue: iframe loads, "ready" message received, code prop changes trigger re-render
- Check DesignView.vue polling: design with `status: "generating"` polls every 1s, stops on `"ready"`
- Test both mobile and desktop layout modes

### Session 7 — Full E2E Integration Test

**Goal**: Run the complete flow end-to-end (import → configure → prompt → generate → preview).

- Run `make test-e2e` — verify both health and design-workflow feature files pass
- If Scenario 2 ("Generate a design from a prompt") fails, debug and fix the integration gap
- Verify the E2E test confirms: design page loads, preview shows empty state during generation, preview shows rendered design after generation completes
- Check for console errors in both scenarios
- If any step broke during Sessions 1-6, fix the integration here

### Session 8 — Improve/Chat Flow (Stretch)

**Goal**: Wire up the design improvement (chat) flow in the frontend.

- Backend already has: `POST /api/designs/:id/improve`, `Design#improve`, chat messages with author/state
- Frontend DesignView.vue fetches design data including `chat` but doesn't render chat messages
- Add chat message display to DesignView (show user prompts + AI responses)
- Add input for improvement prompts that calls `/api/designs/:id/improve`
- Poll for updated iterations during improvement (same as initial generation)
- Add E2E test for the improve flow

## `@slot` Convention — Children Placement in Components

Components in Figma often contain a placeholder instance where child content should be inserted at runtime. Without a convention, `ReactFactory` generates the placeholder as a regular component reference and appends `{props.children}` at the very end of the JSX — outside the component's layout. This means children render as siblings instead of nesting inside the parent's intended slot area.

### The Rule

If a Figma component contains a child instance whose name starts with `@slot`, that instance marks the **default children insertion point**. During React code generation, `ReactFactory` must:

1. **Replace** the `@slot` instance with `{props.children}` in the generated JSX, at the exact position it appears in the component tree.
2. **Omit** the automatic `{props.children}` that `build_component_code` normally appends at the end, since children are now placed inline.

### Example

Figma structure of a `Page` component:
```
Page (COMPONENT_SET)
  └─ Default variant (COMPONENT)
       ├─ Background (RECTANGLE)
       └─ @slot (INSTANCE of some placeholder component)
```

Generated React code **before** (current behavior):
```jsx
export function Page(props) {
  return (
    <>
      <style>{styles}</style>
      <div className="root">
        <div className="background" />
        <Slot />          {/* ← rendered as a component */}
      </div>
      {props.children}    {/* ← always at the end, outside layout */}
    </>
  );
}
```

Generated React code **after** (with `@slot` convention):
```jsx
export function Page(props) {
  return (
    <>
      <style>{styles}</style>
      <div className="root">
        <div className="background" />
        {props.children}  {/* ← replaces @slot, inside the layout */}
      </div>
    </>
  );
}
```

### Impact on Rendering

When the AI generates a tree like `Page > [Title, Text]` and `JsonToJsx` produces:
```jsx
<Page>
  <Title>Danube</Title>
  <Text>2,850 km</Text>
</Page>
```

The children now render inside the Page's layout at the slot position, not as siblings.

### Naming Convention

- Instance name must start with `@slot` (case-sensitive)
- A component can have at most one `@slot` — multiple slots are not supported
- The `@slot` instance can reference any Figma component (its visual content is irrelevant — it's replaced entirely)

## Known Issues
- **Art director disabled**: `ScreenshotJob` no longer triggers `analyze_last_render` — commented out pending re-enablement

## Maintenance Rules

1. **Keep tests up to date**: Write or update tests when changing functionality. Run `make test` before done.
2. **Keep this CLAUDE.md current**: Update when structure, conventions, or architecture change.
3. **Follow existing patterns**: Match code style and testing conventions in each subdirectory.
4. **E2E — no shortcuts**: No API mocks. Clean DB. Data through UI. Full Figma pipeline. Write failing tests first, then fix.
