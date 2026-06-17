# docker-compat.sh — run `docker` / `docker compose` against Apple's `container`
#
# Apple's `container` CLI (1.0.0+) is close to Docker but nests/renames some
# commands, so a plain `alias docker=container` breaks for ps/images/pull/...
# These are shell *functions* (argument-translating "aliases"); works in zsh & bash.
#
# Install:
#   echo 'source "/Users/d8vjork/Projects/OpenSoutheners/OSS/AppleContainerUI/scripts/docker-compat.sh"' >> ~/.zshrc
#   exec zsh   # or open a new terminal
#
# Requires: container (https://github.com/apple/container) and, for compose,
#           container-compose (brew install container-compose).

docker() {
  case "$1" in
    # --- images: Docker keeps these at top level, container nests under `image`
    images)        shift; command container image list "$@" ;;
    rmi)           shift; command container image delete "$@" ;;
    pull)          shift; command container image pull "$@" ;;
    push)          shift; command container image push "$@" ;;
    tag)           shift; command container image tag "$@" ;;
    load)          shift; command container image load "$@" ;;
    save)          shift; command container image save "$@" ;;

    # --- containers
    ps)            shift; command container list "$@" ;;          # add -a for all
    # `docker container <x>` management group -> strip "container", re-dispatch
    container)     shift; docker "$@" ;;

    # --- registry auth
    login)         shift; command container registry login "$@" ;;
    logout)        shift; command container registry logout "$@" ;;

    # --- info / version
    info)          shift; command container system status "$@" ;;
    version|-v|--version) command container --version ;;

    # --- compose (see docker_compose below)
    compose)       shift; command container-compose "$@" ;;

    # Everything else maps 1:1: run, create, start, stop, kill, rm, exec, logs,
    # inspect, stats, cp, build, image, network, volume, system, builder, ...
    *)             command container "$@" ;;
  esac
}

# `docker-compose ...` (the legacy hyphenated binary) -> container-compose
docker-compose() { command container-compose "$@"; }

# NOTE: container-compose (0.12.0) supports only: up, down, build, version.
# `down` is currently broken against runtime 1.0.0 (XPC mismatch) — stop the
# containers individually instead (`docker stop <name>`) until the formula updates.
