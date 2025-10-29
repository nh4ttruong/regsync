PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin
SCRIPT_SRC := regsync.sh
SCRIPT_DST := $(BINDIR)/regsync

.PHONY: install uninstall install-docker install-podman install-helm

install:
	@if [ "$(PREFIX)" = "/usr/local" ]; then \
	  if [ "$(shell id -u)" -ne 0 ]; then \
	    echo "Error: Installing to /usr/local/bin requires root. Use: sudo make install"; \
	    exit 1; \
	  fi; \
	fi
	@command -v helm >/dev/null 2>&1 || { \
	  echo "Error: helm is not installed."; \
	  echo "To install Helm: 'make install-helm' or see https://helm.sh/docs/intro/install/"; \
	  exit 1; \
	}
	@(command -v docker >/dev/null 2>&1 || command -v podman >/dev/null 2>&1) || { \
	  echo "Error: docker or podman is not installed."; \
	  echo "To install Docker: 'make install-docker' or see https://docs.docker.com/get-docker/"; \
	  echo "To install Podman: 'make install-podman' or see https://podman.io/getting-started/installation"; \
	  exit 1; \
	}
	@echo "Installing regsync to $(SCRIPT_DST)"
	install -m 0755 $(SCRIPT_SRC) $(SCRIPT_DST)

uninstall:
	@echo "Removing $(SCRIPT_DST)"
	rm -f $(SCRIPT_DST)

install-docker:
	@echo "Installing Docker via get.docker.com (Linux only)"
	@if [ -z "$(VERSION)" ]; then \
	  curl -fsSL https://get.docker.com | sh ; \
	else \
	  curl -fsSL https://get.docker.com | sh && sudo apt-get install -y docker-ce=$(VERSION) docker-ce-cli=$(VERSION) ; \
	fi

install-helm:
	@echo "Installing Helm via get-helm-3 (Linux only)"
	@if [ -z "$(VERSION)" ]; then \
	  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash ; \
	else \
	  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash -s -- --version v$(VERSION) ; \
	fi

install-podman:
	@echo "Installing Podman (Ubuntu/Debian/RHEL only)"
	@arch=$(shell uname -m); \
	os=$(shell . /etc/os-release && echo $$ID); \
	if [ "$$os" = "ubuntu" ] || [ "$$os" = "debian" ]; then \
	  sudo apt-get update && sudo apt-get install -y podman ; \
	elif [ "$$os" = "rhel" ] || [ "$$os" = "centos" ]; then \
	  sudo yum install -y podman ; \
	else \
	  echo "Please install Podman manually for your OS." ; \
	fi

help:
	@echo "Usage: make install [PREFIX=/custom/path]"
	@echo "       make uninstall"
	@echo "       make install-docker [VERSION=x.y.z]"
	@echo "       make install-podman"
	@echo "       make install-helm [VERSION=x.y.z]"
	@echo "Installs regsync to $(BINDIR) by default."
	@echo "Optional: install Docker, Podman, or Helm (Linux only, version supported)."
