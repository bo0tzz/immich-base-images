# Immich Base Images - wasm-vips Investigation

This repository documents the investigation and solution for building wasm-vips with complete parity to Immich's server native build.

## Quick Start

**Want to build wasm-vips with Immich parity?**

→ See **[WASM_VIPS_COMPLETE_BUILD_GUIDE.md](WASM_VIPS_COMPLETE_BUILD_GUIDE.md)** for step-by-step instructions.

## What's Here

### Complete Build Guide
- **[WASM_VIPS_COMPLETE_BUILD_GUIDE.md](WASM_VIPS_COMPLETE_BUILD_GUIDE.md)** - Start here for end-to-end instructions

### Investigation Documentation
- **[LIBVIPS_IMAGEMAGICK_WASM_INVESTIGATION.md](LIBVIPS_IMAGEMAGICK_WASM_INVESTIGATION.md)** - How ImageMagick integration works (problem, solution, technical details)
- **[WASM_VIPS_JPEGLI_INTEGRATION.md](WASM_VIPS_JPEGLI_INTEGRATION.md)** - How jpegli was integrated with Immich's patches

### Reference Scripts
- **[wasm-vips-reference-scripts/](wasm-vips-reference-scripts/)** - Testing scripts and integration code snippets

## What Was Accomplished

✅ Successfully integrated ImageMagick 7.1.2-2 into wasm-vips via static linking
✅ Achieved complete parity with Immich's server native build
✅ All image formats supported: JPEG, JXL, HEIF, WebP, PNG, TIFF, RAW, GIF, SVG
✅ Same library versions as Immich
✅ Production-ready build process

## Key Insight

ImageMagick integration into wasm-vips requires **static linking** (`-Dmodules=disabled`) because WASM dynamic modules (SIDE_MODULE) are incompatible with ImageMagick's code. This is a WASM platform limitation, not a feature gap - functionality is identical.

## For More Details

See the investigation documents for technical details about:
- Why dynamic modules don't work
- Cross-compilation cache variable workarounds
- jpegli API compatibility issues
- Build configuration details
