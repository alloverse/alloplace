FROM elixir:1.9

WORKDIR /app

RUN apt-get update && apt-get install -y build-essential \
    cmake \
    clang-3.8 \
    git \
    git-lfs \
    libgme-dev \
    libcairo2 libpoppler-glib-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN wget -O cmake-linux.sh https://cmake.org/files/v3.15/cmake-3.15.4-Linux-x86_64.sh && \
    sh cmake-linux.sh -- --skip-license --prefix=/usr/local && \
    /usr/local/bin/cmake --version

ADD marketplace /app/marketplace

RUN cd marketplace && bash bootstrap.sh

# We can't run generate-version.sh inside of the container :S
# This means you MUST run mix compile on the outside of the container before building!!
COPY _cmake/src/allonet/include /app/_cmake/src/allonet/include

ADD . /app/

RUN mix local.hex --force

RUN mix deps.get

RUN mix compile

CMD mix run --no-halt
