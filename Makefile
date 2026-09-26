.PHONY: build test fmt fmt-check ci

build:
	forge build

test:
	forge test

fmt:
	forge fmt

fmt-check:
	forge fmt --check

ci: fmt-check build test
