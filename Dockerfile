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


# make sure fetch apps always fetches the latest
ADD "https://www.random.org/cgi-bin/randbyte?nbytes=10&format=h" skipcache
RUN git clone --recursive https://github.com/alloverse/allo-marketplace.git marketplace
RUN cd marketplace && ./allo/assist fetch && ./fetch-apps.sh

ADD . /app/

RUN mix local.hex --force

RUN mix deps.get

RUN mix compile

CMD mix run --no-halt
