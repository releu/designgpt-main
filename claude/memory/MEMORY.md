# Design-GPT Project Memory

## E2E Test Setup
- 12 tests pass in ~13s: 9 quick UI tests (add phase) + 1 full Figma import + 2 health
- DB starts with ONLY users fixture (alice). No library/component fixtures loaded.
- Tests create all data through the UI — same as real usage
- Real Figma API calls: FIGMA_ACCESS_TOKEN + FIGMA_TOKEN both set in api/.env
- api/config/boot.rb loads dotenv (Dotenv.load) for dev/test; production uses env vars
- Full sync pipeline runs (no E2E bypass). Queue adapter: :async (background threads)
- Console error tracking: `trackConsoleErrors(page)` in each test describe block
- `reuseExistingServer: false` for Rails and Vite in playwright.config.js

## Auth Token
- File: `app/src/test-support/mock-auth0.js`
- Valid HMAC-SHA256 signature: `ZalIPFLH0chqBAwO-wWOrBy3G6EBN8s-JGKRZ0rh0IE`
- Secret: `e2e-test-secret-key` (matches Rails `E2E_JWT_SECRET` default)

## Key Bugs Fixed
1. `app/index.html`: removed broken `<link rel="apple-touch-icon" href="/touch-icon-iphone.png">` (file missing → 404 console error)
2. `app/src/components/DesignSystemModal.vue`: fixed race condition (lib.loading = false moved into finally block after loadComponents)
3. `app/src/components/DesignSystemModal.vue`: added guards `if (!createRes.ok) continue` and `if (!lib.id) continue`
4. `app/src/views/HomeView.vue`: added `.then((res) => (res.ok ? res.json() : []))` guards for API responses
5. `api/app/controllers/component_libraries_controller.rb` create: rescue RecordNotUnique → return existing library

## Fixture Data for Tests
- Libraries: "Example Lib" (figma_file_key: 75U91YIrYa65xhYcM0olH5) and "Example Icons" (dlYQK7x0jXbn8HCFFvZ0lw)
- Button variants: "Size=M, State=default" and "Size=M, State=hover" → props: Size=[M], State=[default, hover]
- Icon sets (is_icon: true from contains_only_vectors? check): IconArrow, IconClose

## Architecture Notes
- Designs link to DesignSystem (not ComponentLibrary directly)
- `is_root` / `allowed_children` auto-set at import time from Figma conventions; no manual UI
- Background jobs don't run in test mode (`:test` queue adapter)
- `sync_async` resets status to "pending" in production, skipped in E2E test mode

## Figma Conventions (affect import + codegen)
- `#root` in name/description → `is_root = true` at import
- INSTANCE_SWAP + `preferredValues` → bound instance becomes `{props.children}`; `preferredValues` keys resolved to `allowed_children`
- `#list` in name/description → N identical INSTANCE_SWAP instances collapsed to one `{props.children}`; schema uses direct `$ref`
- `@slot` name prefix → removed (no backward compat)
- ComponentDetail.vue shows is_root/allowed_children as read-only info (no edit controls)

## Common Patterns
- Rails test controller guard: `unless Rails.env.test? && ENV["E2E_TEST_MODE"] == "true"`
- Vue auth: `setup() { const { getAccessTokenSilently } = useAuth0(); return { getAccessTokenSilently }; }`
- Always need both `app.provide(AUTH0_INJECTION_KEY, auth0State)` AND `app.config.globalProperties.$auth0 = auth0State`
