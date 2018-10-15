PACKAGE  = github.com/Azure/azure-amqp-common-go
DATE    ?= $(shell date +%FT%T%z)
VERSION ?= $(shell git describe --tags --always --dirty --match=v* 2> /dev/null || \
			cat $(CURDIR)/.version 2> /dev/null || echo v0)
BIN      = $(GOPATH)/bin
BASE     = $(GOPATH)/src/$(PACKAGE)
PKGS     = $(or $(PKG),$(shell cd $(BASE) && env GOPATH=$(GOPATH) $(GO) list ./... | grep -vE "^$(PACKAGE)/vendor|_examples|templates/"))
TESTPKGS = $(shell env GOPATH=$(GOPATH) $(GO) list -f '{{ if or .TestGoFiles .XTestGoFiles }}{{ .ImportPath }}{{ end }}' $(PKGS))
GO_FILES = find . -iname '*.go' -type f | grep -v /vendor/

GO      = go
GODOC   = godoc
GOFMT   = gofmt
GOCYCLO = gocyclo
DEP   	= dep

V = 0
Q = $(if $(filter 1,$V),,@)
M = $(shell printf "\033[34;1m▶\033[0m")
TIMEOUT = 360

.PHONY: all
all: fmt vendor lint vet megacheck | $(BASE) ; $(info $(M) building library…) @ ## Build program
	$Q cd $(BASE) && $(GO) build ./... \
		-tags release \
		-ldflags '-X $(PACKAGE)/cmd.Version=$(VERSION) -X $(PACKAGE)/cmd.BuildDate=$(DATE)'

$(BASE): ; $(info $(M) setting GOPATH…)
	@mkdir -p $(dir $@)
	@ln -sf $(CURDIR) $@

# Tools

GOLINT = $(BIN)/golint
$(BIN)/golint: | $(BASE) ; $(info $(M) building golint…)
	$Q go get -u golang.org/x/lint/golint

# Tests

TEST_TARGETS := test-default test-bench test-short test-verbose test-race test-debug
.PHONY: $(TEST_TARGETS) test-xml check test tests
test-bench:   ARGS=-run=__absolutelynothing__ -bench=. ## Run benchmarks
test-short:   ARGS=-short        ## Run only short tests
test-verbose: ARGS=-v            ## Run tests in verbose mode
test-debug:   ARGS=-v -debug     ## Run tests in verbose mode with debug output
test-race:    ARGS=-race         ## Run tests with race detector
test-cover:   ARGS=-cover     ## Run tests in verbose mode with coverage
$(TEST_TARGETS): NAME=$(MAKECMDGOALS:test-%=%)
$(TEST_TARGETS): test
check test tests: cyclo lint vet vendor megacheck | $(BASE) ; $(info $(M) running $(NAME:%=% )tests…) @ ## Run tests
	$Q cd $(BASE) && $(GO) test -timeout $(TIMEOUT)s $(ARGS) $(TESTPKGS)

.PHONY: vet
vet: vendor | $(BASE) $(GOLINT) ; $(info $(M) running vet…) @ ## Run vet
	$Q cd $(BASE) && $(GO) vet ./...

.PHONY: lint
lint: vendor | $(BASE) $(GOLINT) ; $(info $(M) running golint…) @ ## Run golint
	$Q cd $(BASE) && ret=0 && for pkg in $(PKGS); do \
		test -z "$$($(GOLINT) $$pkg | tee /dev/stderr)" || ret=1 ; \
	 done ; exit $$ret

.PHONY: megacheck
megacheck: vendor | $(BASE) ; $(info $(M) running megacheck…) @ ## Run megacheck
	$Q cd $(BASE) && megacheck

.PHONY: fmt
fmt: ; $(info $(M) running gofmt…) @ ## Run gofmt on all source files
	@ret=0 && for d in $$($(GO) list -f '{{.Dir}}' ./... | grep -v /vendor/); do \
		$(GOFMT) -l -w $$d/*.go || ret=$$? ; \
	 done ; exit $$ret

.PHONY: cyclo
cyclo: ; $(info $(M) running gocyclo...) @ ## Run gocyclo on all source files
	$Q cd $(BASE) && $(GOCYCLO) -over 19 $$($(GO_FILES))
# Dependency management

Gopkg.lock: Gopkg.toml | $(BASE) ; $(info $(M) updating dependencies…)
	$Q cd $(BASE) && $(DEP) ensure
	@touch $@
vendor: Gopkg.lock | $(BASE) ; $(info $(M) retrieving dependencies…)
	$Q cd $(BASE) && $(DEP) ensure
	@touch $@

# Misc

.PHONY: clean
clean: ; $(info $(M) cleaning…)	@ ## Cleanup everything
	@rm -rf test/tests.* test/coverage.*

.PHONY: help
help:
	@grep -E '^[ a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

.PHONY: version
version:
	@echo $(VERSION)