# Vendored Opus 1.6.1

Official source: https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz
BSD license: COPYING. Portable floating point codec from OPUS_SOURCES,
OPUS_SOURCES_FLOAT, CELT_SOURCES, SILK_SOURCES and SILK_SOURCES_FLOAT.
The optional DRED/deep PLC models and CPU-specific assemblers are disabled.

Local Xcode 27 compatibility changes (2026-10-16): correct quant_all_bands
parameter documentation, explicitly initialize loop-dependent locals, and make
bounded int32 conversions explicit. These do not change valid-frame encoding,
the Opus bitstream, or the wire protocol. The iOS pod omits silk/debug.c because
SILK_DEBUG and SILK_TIC_TOC are disabled; the portable source manifest is retained.
