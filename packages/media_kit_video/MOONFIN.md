This local package is copied from RadicalMuffinMan/media-kit at
50013aee7429633ae2df656982167ca6d21237ce, directory media_kit_video (2.0.1).
The upstream MIT LICENSE is preserved. No examples or tests are vendored.

Moonfin changes:
- Remove `resolution: workspace` for use as a local path dependency.
- Add an optional Windows Facebetter 2.1.1 processor and method channel.
- In hardware rendering, read back the actual ANGLE presentation framebuffer,
  process SDR pixels in the SDK's own GL context, and draw the output before
  Flutter receives the texture. Restore EGL and GL state after processing.
  The software render fallback also processes each presented RGBA frame.
  The engine is created, used, and released on the render worker.
- Correct multiplication order in the software renderer's aspect-ratio scaling
  and set the unused rgb0 alpha byte to opaque for Flutter.

Other platform implementations are retained from the pinned upstream commit.
Facebetter is a separately licensed binary dependency; its engine is not covered
by this package's MIT license. See docs/facebetter-desktop-ios.md at the app root.
