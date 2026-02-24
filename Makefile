.PHONY: dev test test-api test-app test-e2e setup setup-e2e

# Start all development servers (Rails API + Vite frontend + Caddy proxy)
dev:
	@trap 'kill 0' EXIT; \
	cd api && bin/rails server -p 3000 -b 127.0.0.1 & \
	cd app && npm run dev & \
	cd caddy && caddy run --config Caddyfile & \
	wait

# Run all test layers
test: test-api test-app

# Layer 1: API unit/integration tests (RSpec)
test-api:
	cd api && bundle exec rspec

# Layer 2: Frontend unit tests (Vitest)
test-app:
	cd app && npm test

# Layer 3: E2E integration tests (Playwright)
# Starts Rails, Vite, and Caddy automatically
test-e2e:
	cd api && RAILS_ENV=test bundle exec rails db:test:prepare
	cd api && RAILS_ENV=test E2E_TEST_MODE=true bundle exec rails e2e:setup
	cd e2e && npx bddgen && npx playwright test

# Install E2E dependencies
setup-e2e:
	cd e2e && npm install && npx playwright install chromium

# Install all dependencies
setup:
	cd app && npm install
	cd api && bundle install
	$(MAKE) setup-e2e
