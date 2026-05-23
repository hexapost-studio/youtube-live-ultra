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
.PHONY: install-cli install-resilience install-dashboard install-tui install-all
.PHONY: deps-cli deps-resilience deps-dashboard deps-tui deps-all

all: check test

help:
	@echo "$(CYAN)youtube-live-ultra v$(VERSION)$(NC)"
	@echo ""
	@echo "Installation (choisis ton tier) :"
	@echo "  make install-cli         CLI pure (~50 MB)"
	@echo "  make install-resilience   + Watchdog IPC"
	@echo "  make install-dashboard    + Dashboard web (stats, chat)"
	@echo "  make install-tui          + Terminal UI"
	@echo "  make install-all          Complet (~70 MB)"
	@echo ""
	@echo "Développement :"
	@echo "  make test        Run test suite (bats)"
	@echo "  make lint        Run shellcheck"
	@echo "  make check       Lint + test"
	@echo "  make clean       Remove artifacts"
	@echo ""

# ─── DEPENDENCIES ────────────────────────────────────────────────────────────

deps-cli:
	@echo "$(GREEN)Installation dépendances CLI...$(NC)"
	@if command -v brew >/dev/null 2>&1; then \
		brew install streamlink mpv yt-dlp curl; \
	elif command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get install -y streamlink mpv yt-dlp curl; \
	fi

deps-resilience:
	@echo "$(GREEN)Installation dépendances résilience...$(NC)"
	@if command -v brew >/dev/null 2>&1; then \
		brew install socat bc; \
	elif command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get install -y socat bc; \
	fi

deps-dashboard:
	@echo "$(GREEN)Installation dépendances dashboard...$(NC)"
	@if command -v brew >/dev/null 2>&1; then \
		brew install python3; \
	elif command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get install -y python3 python3-pip; \
	fi
	@pip3 install flask flask-sock

deps-tui:
	@echo "$(GREEN)Installation dépendances TUI...$(NC)"
	@if command -v brew >/dev/null 2>&1; then \
		brew install dialog; \
	elif command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get install -y dialog; \
	fi

deps-all: deps-cli deps-resilience deps-dashboard deps-tui

# ─── INSTALL BY TIER ─────────────────────────────────────────────────────────

install-cli: deps-cli
	@for script in watch.sh watch-ultra.sh watch-ytdlp.sh; do \
		cp "$$script" "$(BINDIR)/youtube-live-$$(basename $$script)"; \
		chmod 755 "$(BINDIR)/youtube-live-$$(basename $$script)"; \
		echo "  $(GREEN)✓$(NC) $(BINDIR)/youtube-live-$$(basename $$script)"; \
	done
	@for helper in scripts/health-check.sh scripts/optimize-network.sh scripts/benchmark-latency.sh; do \
		cp "$$helper" "$(BINDIR)/"; chmod 755 "$(BINDIR)/$$(basename $$helper)"; \
		echo "  $(GREEN)✓$(NC) $(BINDIR)/$$(basename $$helper)"; \
	done
	@mkdir -p "$(CONFDIR)" && cp config/mpv.conf "$(CONFDIR)/"
	@echo "$(GREEN)CLI installé. Lance : youtube-live-watch.sh <URL>$(NC)"

install-resilience: install-cli deps-resilience
	@cp watch-resilient.sh "$(BINDIR)/youtube-live-watch-resilient.sh"
	@chmod 755 "$(BINDIR)/youtube-live-watch-resilient.sh"
	@echo "$(GREEN)Résilience installée. Lance : youtube-live-watch-resilient.sh <URL> --mode ultra$(NC)"

install-dashboard: install-resilience deps-dashboard
	@cp watch-dashboard.sh "$(BINDIR)/youtube-live-watch-dashboard.sh"
	@chmod 755 "$(BINDIR)/youtube-live-watch-dashboard.sh"
	@cp -r dashboard "$(CONFDIR)/dashboard"
	@echo "$(GREEN)Dashboard installé. Lance : youtube-live-watch-dashboard.sh <URL>$(NC)"

install-tui: install-resilience deps-tui
	@echo "$(GREEN)TUI — à venir (watch-tui.sh)$(NC)"

install-all: install-dashboard install-tui
	@echo "$(GREEN)✅ Installation complète$(NC)"

# ─── SYSTEM INSTALL ──────────────────────────────────────────────────────────
install: install-all

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
