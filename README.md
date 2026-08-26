# swift-ndi

A memory-safe, type-safe, and concurrency-safe Swift wrapper for the [NDI SDK](https://docs.ndi.video/all/developing-with-ndi/sdk).

## NDI SDK and runtime setup

This package provides a Swift interface to NDI, but does not redistribute the NDI SDK headers or binary. Install the NDI SDK for Apple before building, and review NDI's [software distribution requirements](https://docs.ndi.video/all/developing-with-ndi/sdk/software-distribution) before shipping its libraries with an application.

### iOS and tvOS

NDI must be statically linked on iOS and tvOS. Add the SDK's platform-specific static library (`libndi_ios.a` or `libndi_tvos.a`) to the application target that consumes the `NDI` product. These platforms do not load the NDI runtime dynamically.

### macOS

On macOS, the package loads `libndi.dylib` at runtime. For an application bundle, the recommended setup is to embed the library in the app:

1. Add the NDI SDK's `libndi.dylib` to the application target.
2. Embed it at `Contents/Frameworks/libndi.dylib` using a Copy Files build phase whose destination is **Frameworks**, with **Code Sign on Copy** enabled.
3. Keep `@executable_path/../Frameworks` in the target's Runpath Search Paths. This is included in Xcode's usual application defaults.

Embedding gives the application a known runtime version and works with the Hardened Runtime and App Sandbox, which may prevent access to libraries installed elsewhere on the system. Ensure that distributing the embedded library complies with the NDI SDK license.

The loader checks the following locations, in order:

1. `@executable_path/../Frameworks/libndi.dylib`
2. The directory named by `NDI_RUNTIME_DIR_V6`
3. `/Library/NDI SDK for Apple/lib/macOS/libndi.dylib`
4. `/usr/local/lib/libndi.dylib`
5. `libndi.dylib` through the normal dyld search paths

The installed paths and `NDI_RUNTIME_DIR_V6` are useful for development tools and non-sandboxed executables, but applications should not depend on an end user having the SDK or redistributable installed system-wide. See NDI's [Dynamic Loading of NDI Libraries](https://docs.ndi.video/all/developing-with-ndi/sdk/dynamic-loading-of-ndi-libraries) documentation for the official runtime-loading guidance.
