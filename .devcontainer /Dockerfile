FROM dart

RUN apt-get update
RUN apt-get install -y curl git unzip xz-utils zip libglu1-mesa

RUN apt-get clean

# Pin the Flutter SDK version to match the version in `.github/workflows/tests.yml`
RUN git clone https://github.com/flutter/flutter.git -b 3.32.5 --depth 1 /flutter
ENV PATH="/flutter/bin:$PATH"
RUN flutter doctor