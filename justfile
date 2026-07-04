default:
    @just --list

dev:
    swift run smacro-gui

test:
    swift test

build:
    swift build

e2e:
    scripts/validate-swift-proto.sh

app-smoke:
    scripts/validate-app-bundle.sh

install *args:
    scripts/build-app.sh {{args}}
