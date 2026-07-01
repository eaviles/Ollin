#!/bin/sh
# Wipe the caches Ollin accumulates on disk.
#
# With no target flags it clears the two runtime caches that regenerate
# automatically and cheaply, so clearing them is always safe; it just reclaims
# space (and forces a fresh download/bake/compile):
#
#   --environments     HDRI environments: downloaded HDRIs plus their decoded
#                      pixel blobs, under ~/Library/Caches/Ollin/Environments/
#                      (honoring OLLIN_ENVIRONMENT_CACHE).
#   --compiled-models  Compiled Core ML models: ~/Library/Caches/Ollin/CompiledModels/
#                      (the stable .mlmodelc the model trackers specialize once
#                      and reuse).
#
# Two more targets are heavier to get back, so they're never in the default set:
#
#   --models   the fetched ML model weights in Models/ (a network re-download
#              via Scripts/fetch-models.sh).
#   --build    the SwiftPM build cache in .build/ (often many GB; the next
#              build is a full recompile).
#
# Pass any combination of targets to clear exactly those; --all selects every
# target. With no target, the two runtime caches above are cleared.
#
# Usage:
#   Scripts/clear-caches.sh                    clear environments + compiled models
#   Scripts/clear-caches.sh --environments     clear only the HDRI environment cache
#   Scripts/clear-caches.sh --compiled-models  clear only the compiled-model cache
#   Scripts/clear-caches.sh --models --build   clear the fetched weights and build cache
#   Scripts/clear-caches.sh --all              clear every cache (env + compiled + models + build)
#   Scripts/clear-caches.sh --dry-run          show what would be removed, remove nothing
set -e
cd "$(git rev-parse --show-toplevel)"

DO_ENV=false
DO_COMPILED=false
DO_MODELS=false
DO_BUILD=false
ANY_TARGET=false
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --environments)    DO_ENV=true;      ANY_TARGET=true ;;
    --compiled-models) DO_COMPILED=true; ANY_TARGET=true ;;
    --models)          DO_MODELS=true;   ANY_TARGET=true ;;
    --build)           DO_BUILD=true;    ANY_TARGET=true ;;
    --all)             DO_ENV=true; DO_COMPILED=true; DO_MODELS=true; DO_BUILD=true; ANY_TARGET=true ;;
    --dry-run)         DRY_RUN=true ;;
    -h|--help)
      awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
      exit 0 ;;
    *)
      echo "unknown option: $arg (try --help)" >&2
      exit 1 ;;
  esac
done

# With no explicit target, clear the two safe auto-regenerating caches.
if [ "$ANY_TARGET" = false ]; then
  DO_ENV=true
  DO_COMPILED=true
fi

CACHES="${HOME}/Library/Caches/Ollin"
ENV_CACHE="${OLLIN_ENVIRONMENT_CACHE:-${CACHES}/Environments}"
MODEL_CACHE="${CACHES}/CompiledModels"

# Remove a directory's contents, reporting its size first. A missing or empty
# directory is reported and skipped, never an error.
clear_dir() {
  label="$1"
  dir="$2"
  if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
    echo "· $label: nothing to clear ($dir)"
    return
  fi
  size="$(du -sh "$dir" 2>/dev/null | cut -f1)"
  if [ "$DRY_RUN" = true ]; then
    echo "would clear $label: $size ($dir)"
  else
    rm -rf "${dir:?}"
    echo "✓ cleared $label: $size ($dir)"
  fi
}

# Ollin's entries in the environment cache: the <16-hex-hash>- prefixed downloads
# and the .equirectf16 decoded-pixel blobs (plus their atomic-write temps, which
# share those prefixes/suffixes).
env_cache_files() {
  find "$1" -maxdepth 1 -type f \
    \( -name '????????????????-*' -o -name '*.equirectf16' \) 2>/dev/null
}

# Clear only Ollin's own files from the environment cache. OLLIN_ENVIRONMENT_CACHE
# may point the cache at a user-chosen (possibly shared) directory, so removing the
# directory wholesale could take unrelated files with it; delete by pattern instead.
clear_env_cache() {
  label="$1"
  dir="$2"
  if [ ! -d "$dir" ] || [ -z "$(env_cache_files "$dir")" ]; then
    echo "· $label: nothing to clear ($dir)"
    return
  fi
  count="$(env_cache_files "$dir" | wc -l | tr -d ' ')"
  size="$(env_cache_files "$dir" | tr '\n' '\0' | xargs -0 du -ch 2>/dev/null | tail -1 | cut -f1)"
  if [ "$DRY_RUN" = true ]; then
    echo "would clear $label: $count files, $size ($dir)"
  else
    env_cache_files "$dir" | tr '\n' '\0' | xargs -0 rm -f
    echo "✓ cleared $label: $count files, $size ($dir)"
  fi
}

if [ "$DO_ENV" = true ]; then
  clear_env_cache "HDRI environments" "$ENV_CACHE"
fi
if [ "$DO_COMPILED" = true ]; then
  clear_dir "compiled Core ML models" "$MODEL_CACHE"
fi
if [ "$DO_MODELS" = true ]; then
  clear_dir "fetched ML model weights" "Models"
  [ "$DRY_RUN" = true ] || echo "  (re-fetch with Scripts/fetch-models.sh)"
fi
if [ "$DO_BUILD" = true ]; then
  clear_dir "SwiftPM build cache" ".build"
  [ "$DRY_RUN" = true ] || echo "  (the next build is a full recompile)"
fi
