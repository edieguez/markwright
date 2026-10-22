NVIM ?= nvim
STYLUA ?= stylua
SELENE ?= selene
SRC := lua plugin tests

.PHONY: test fmt lint check

test:
	$(NVIM) --headless -u tests/minimal_init.lua -c "lua dofile('tests/run.lua')"

fmt:
	$(STYLUA) $(SRC)

lint:
	$(STYLUA) --check $(SRC)
	$(SELENE) $(SRC)

check: lint test
