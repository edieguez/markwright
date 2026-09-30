NVIM ?= nvim

.PHONY: test
test:
	$(NVIM) --headless -u tests/minimal_init.lua -c "lua dofile('tests/format_spec.lua')"
