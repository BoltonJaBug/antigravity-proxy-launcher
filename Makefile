.PHONY: build test install clean

build:
	./scripts/build-app.sh

test:
	./scripts/test.sh

install:
	./scripts/install.sh

clean:
	rm -rf build
