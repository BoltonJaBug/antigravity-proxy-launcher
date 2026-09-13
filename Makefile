.PHONY: build test build-menu test-menu install install-menu clean

build:
	./scripts/build-app.sh

test:
	./scripts/test.sh

build-menu:
	./scripts/build-menubar-app.sh

test-menu:
	./scripts/test-menubar.sh

install:
	./scripts/install.sh

install-menu:
	./scripts/install-menubar.sh

clean:
	rm -rf build
