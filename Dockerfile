FROM elixir:1.9

WORKDIR /app

RUN apt-get update && apt-get install -y build-essential \
    cmake \
    clang-3.8 \
    git \
    libgme-dev \
    libcairo2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN wget -O cmake-linux.sh https://cmake.org/files/v3.15/cmake-3.15.4-Linux-x86_64.sh && \
    sh cmake-linux.sh -- --skip-license --prefix=/usr/local && \
    /usr/local/bin/cmake --version

ADD . /app/

RUN cd alloapps/jukebox; ./allo/assist fetch
RUN cd alloapps/drawing-board; ./allo/assist fetch
RUN cd alloapps/clock; ./allo/assist fetch

RUN mix local.hex --force

RUN mix deps.get

RUN mix compile

CMD mix run --no-halt
