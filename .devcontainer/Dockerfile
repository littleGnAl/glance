# .devcontainer/Dockerfile
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Install system deps for Flutter desktop/web
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl unzip git xz-utils libgtk-3-dev libblkid-dev \
      liblzma-dev libxcb-xinput0 libglu1-mesa \
 && rm -rf /var/lib/apt/lists/*

# NOTE: Pin the Flutter SDK version to match the version in `.github/workflows/tests.yml`
ENV FLUTTER_VERSION=3.32.5
RUN git clone --depth 1 --branch $FLUTTER_VERSION https://github.com/flutter/flutter.git /opt/flutter

# Add to PATH
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Pre-download Dart/Flutter binaries to speed up first launch
RUN flutter --version \
 && flutter config --enable-web --no-analytics \
 && flutter doctor --verbose || true
