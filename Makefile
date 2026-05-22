# =============================================================================
# youtube-live-ultra — Makefile
# Targets: install, uninstall, test, lint, clean, release
# =============================================================================

PREFIX       ?= /usr/local
BINDIR       ?= $(PREFIX)/bin
CONFDIR      ?= $(PREFIX)/etc/youtube-live-ultra
DOCDIR       ?= $(PREFIX)/share/doc/youtube-live-ultra
USER_CONFDIR ?= $(HOME)/.config/youtube-live-ultra

VERSION      := $(shell cat VERSION 2>/dev/null || echo "dev")
SCRIPTS      := $(wildcard watch*.sh)
HELPERS      := $(wildcard scripts/*.sh)

# Colors
GREEN  := \033[0;32m
RED    := \033[0;31m
CYAN   := \033[0;36m
NC     := \033[0m

.PHONY: all install uninstall test lint clean check release help

all: check test

help:
	@echo "$(CYAN)youtube-live-ultra v$(VERSION)$(NC)"
	@echo ""
	@echo "Targets:"
	@echo "  make install     Install system-wide ($(BINDIR))"
	@echo "  make install-user Install for current user only ($(USER_CONFDIR))"
	@echo "  make uninstall   Remove system-wide installation"
	@echo "  make test        Run test suite (requires bats)"
	@echo "  make lint        Run shellcheck on all scripts"
	@echo "  make check       Run lint + test"
	@echo "  make clean       Remove build artifacts"
	@echo "  make release     Tag and push a new release"
	@echo ""

# ─── INSTALL ─────────────────────────────────────────────────────────────────

install:
	@echo "$(GREEN)Installing youtube-live-ultra v$(VERSION)...$(NC)"
	@mkdir -p "$(BINDIR)" "$(CONFDIR)" "$(DOCDIR)"
	@# Install scripts
	@for script in $(SCRIPTS); do \
		cp "$$script" "$(BINDIR)/youtube-live-$$(basename $$script)"; \
		chmod 755 "$(BINDIR)/youtube-live-$$(basename $$script)"; \
		echo "  $(GREEN)✓$(NC) $(BINDIR)/youtube-live-$$(basename $$script)"; \
	done
	@for helper in $(HELPERS); do \
		cp "$$helper" "$(BINDIR)/"; \
		chmod 755 "$(BINDIR)/$$(basename $$helper)"; \
		echo "  $(GREEN)✓$(NC) $(BINDIR)/$$(basename $$helper)"; \
	done
	@# Install config
	@cp config/mpv.conf "$(CONFDIR)/mpv.conf"
	@echo "  $(GREEN)✓$(NC) $(CONFDIR)/mpv.conf"
	@# Install docs
	@cp README.md CHANGELOG.md "$(DOCDIR)/"
	@echo "  $(GREEN)✓$(NC) Documentation installed"
	@echo ""
	@echo "$(GREEN)Installation complete.$(NC)"
	@echo "  Run: youtube-live-watch.sh <URL>"

install-user:
	@echo "$(GREEN)Installing for current user...$(NC)"
	@mkdir -p "$(USER_CONFDIR)"
	@cp config/mpv.conf "$(USER_CONFDIR)/mpv.conf" 2>/dev/null || true
	@echo "  $(GREEN)✓$(NC) Config: $(USER_CONFDIR)/"
	@echo "  Run from project directory: ./watch.sh <URL>"
	@echo "  Or add to PATH: export PATH=\"$(PWD):\$$PATH\""

uninstall:
	@echo "$(RED)Uninstalling youtube-live-ultra...$(NC)"
	@for script in $(SCRIPTS); do \
		rm -f "$(BINDIR)/youtube-live-$$(basename $$script)"; \
	done
	@for helper in $(HELPERS); do \
		rm -f "$(BINDIR)/$$(basename $$helper)"; \
	done
	@rm -rf "$(CONFDIR)" "$(DOCDIR)"
	@echo "$(RED)Uninstall complete.$(NC)"

# ─── TEST ────────────────────────────────────────────────────────────────────

test:
	@if command -v bats >/dev/null 2>&1; then \
		echo "$(CYAN)Running tests...$(NC)"; \
		bats --recursive tests/; \
	elif [ -f tests/test_suite.sh ]; then \
		echo "$(CYAN)Running tests (bash fallback)...$(NC)"; \
		bash tests/test_suite.sh; \
	else \
		echo "$(RED)bats not installed. Install with: brew install bats-core$(NC)"; \
		exit 1; \
	fi

# ─── LINT ────────────────────────────────────────────────────────────────────

lint:
	@echo "$(CYAN)Linting shell scripts...$(NC)"
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x $(SCRIPTS) $(HELPERS); \
		echo "$(GREEN)✓ All scripts pass shellcheck$(NC)"; \
	else \
		echo "$(RED)shellcheck not installed. Install with: brew install shellcheck$(NC)"; \
		for f in $(SCRIPTS) $(HELPERS); do \
			echo "  Checking $$f (bash -n)..."; \
			bash -n "$$f" || exit 1; \
		done; \
		echo "$(GREEN)✓ Syntax check passed (install shellcheck for full linting)$(NC)"; \
	fi

# ─── CHECK ───────────────────────────────────────────────────────────────────

check: lint test
	@echo ""
	@echo "$(GREEN)All checks passed ✓$(NC)"

# ─── CLEAN ───────────────────────────────────────────────────────────────────

clean:
	@rm -rf /tmp/youtube-live-ultra-logs /tmp/youtube-live-ultra.lock /tmp/youtube-live-benchmark-*
	@echo "$(GREEN)Clean complete.$(NC)"

# ─── RELEASE ─────────────────────────────────────────────────────────────────

release:
	@if [ -z "$(VERSION)" ] || [ "$(VERSION)" = "dev" ]; then \
		echo "$(RED)No VERSION file or version is 'dev'. Set VERSION before releasing.$(NC)"; \
		exit 1; \
	fi
	@if ! git diff-index --quiet HEAD --; then \
		echo "$(RED)Working directory is dirty. Commit or stash changes first.$(NC)"; \
		exit 1; \
	fi
	@echo "$(GREEN)Releasing v$(VERSION)...$(NC)"
	git tag -a "v$(VERSION)" -m "Release v$(VERSION)"
	git push origin "v$(VERSION)"
	@echo "$(GREEN)Tag v$(VERSION) pushed. Create release on GitHub.$(NC)"
