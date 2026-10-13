# Vendored RNNoise

Source: https://github.com/xiph/rnnoise, tag v0.1, commit
`cdf196b1e9de2f8ff1003328ebf9a4316477429d`. BSD 3-clause license: COPYING.
The original source and built-in model are unmodified. Only library sources and headers are included.
This compact model runs offline on Android; it does not upload microphone audio or download weights.
The small v0.1 model is selected to limit CPU and memory pressure during Bluetooth audio/data coexistence.
DawnMesh wraps the 48 kHz / 480-sample API with streaming resampling and optional wind filtering.
The license is also distributed in APK assets as RNNoise-LICENSE.txt.

The iOS port prefixes the bundled CELT/FFT helpers in src/arch.h to avoid symbol collisions with linked libopus.
The three CELT-derived C files are renamed rnnoise_pitch.c, rnnoise_kiss_fft.c and rnnoise_celt_lpc.c to keep Xcode object filenames distinct from libopus.
