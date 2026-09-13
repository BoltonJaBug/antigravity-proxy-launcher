.PHONY: build test build-menu test-menu install install-menu clean

build:
	./scripts/build-app.sh

test:
	./scripts/test.sh

build-menu:
	./scripts/build-app.sh

test-menu:
	./scripts/test-menubar.sh

install:
	./scripts/install.sh

install-menu:
	./scripts/install.sh

clean:
	rm -rf build build-menu build-menu-test
