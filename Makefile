.PHONY: install test

install:
	./install.sh

test:
	bash -n install.sh bin/codex tests/test_install.sh
	python3 -m unittest -v tests/test_codex_account.py
	bash tests/test_install.sh
