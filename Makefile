# Makefile for vrecord (BCS1212). A bare 'make' only shows help.
PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/share/vrecord
COMPDIR ?= /etc/bash_completion.d
DESTDIR ?=
SUITE   ?=

# Directory of this Makefile (trailing slash). Anchors source paths so
# 'make install' works regardless of invoking CWD.
srcdir := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

PROGRAMS := vrecord vrecord-loop

.PHONY: all install uninstall check test lint help

all: help

# vrecord finds the beep in /usr/local/share/vrecord or /usr/share/vrecord.
# Under any other PREFIX, set BEEP_FILE in ~/.vrecord/config.
# config.sample is a reference copy; vrecord never reads it.
install:
	install -d "$(DESTDIR)$(BINDIR)" "$(DESTDIR)$(DATADIR)"
	install -m 755 "$(srcdir)vrecord" "$(DESTDIR)$(BINDIR)/vrecord"
	install -m 755 "$(srcdir)vrecord-loop" "$(DESTDIR)$(BINDIR)/vrecord-loop"
	install -m 644 "$(srcdir)beep.mp3" "$(DESTDIR)$(DATADIR)/beep.mp3"
	install -m 644 "$(srcdir)config.sample" "$(DESTDIR)$(DATADIR)/config.sample"
	if [ -d "$(DESTDIR)$(COMPDIR)" ]; then \
	  install -m 644 "$(srcdir)vrecord-completion.bash" "$(DESTDIR)$(COMPDIR)/vrecord"; \
	fi
	@if [ -z "$(DESTDIR)" ]; then $(MAKE) --no-print-directory check; fi

# Recordings and ~/.vrecord (config, sessions, recovered_*) are user data and
# are never touched. DATADIR is removed only if nothing else is left in it.
uninstall:
	rm -f "$(DESTDIR)$(BINDIR)/vrecord" "$(DESTDIR)$(BINDIR)/vrecord-loop"
	rm -f "$(DESTDIR)$(DATADIR)/beep.mp3" "$(DESTDIR)$(DATADIR)/config.sample"
	rm -f "$(DESTDIR)$(COMPDIR)/vrecord"
	rmdir "$(DESTDIR)$(DATADIR)" 2>/dev/null || true

# Fails if a command is missing or if another copy earlier in PATH would run
# instead of the one in BINDIR.
check:
	@for cmd in $(PROGRAMS); do \
	  found=$$(command -v "$$cmd") || { echo "$$cmd: NOT FOUND (check PATH)"; exit 1; }; \
	  if [ "$$found" != "$(BINDIR)/$$cmd" ]; then \
	    echo "$$cmd: $$found runs instead of $(BINDIR)/$$cmd"; exit 1; \
	  fi; \
	  echo "$$cmd: OK"; \
	done

# Needs a live PulseAudio/PipeWire server. SUITE=<name> runs one suite.
test:
	"$(srcdir)run_tests.sh" $(SUITE)

lint:
	cd "$(srcdir)" && shellcheck -x vrecord vrecord-loop install.sh uninstall.sh \
	  run_tests.sh vrecord-completion.bash tests/test_vrecord.sh tests/lib/*.sh

help:
	@echo 'Usage: make [target] [VARIABLE=value ...]'
	@echo ''
	@echo 'Targets:'
	@echo '  install     Install vrecord and vrecord-loop to $(BINDIR)'
	@echo '  uninstall   Remove installed files (recordings and ~/.vrecord are kept)'
	@echo '  check       Verify the installed commands are the ones found in PATH'
	@echo '  test        Run the test suite (needs an audio server; SUITE=name for one)'
	@echo '  lint        Run shellcheck on all scripts'
	@echo '  help        Show this message'
	@echo ''
	@echo 'Variables:'
	@echo '  PREFIX=$(PREFIX)  BINDIR=$(BINDIR)'
	@echo '  DATADIR=$(DATADIR)  COMPDIR=$(COMPDIR)'
	@echo '  DESTDIR=$(DESTDIR)  SUITE=$(SUITE)'
