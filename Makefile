.PHONY: all test clean
all:
	./scripts/build-app.sh
test: all
	./scripts/test-updater-metadata.sh
	./scripts/test-permissions.sh
	./scripts/test-status-menu.sh
	./scripts/test-native-bridge.sh
	python3 -m unittest discover -s tests -p 'test_*.py'
clean:
	rm -rf build .build
