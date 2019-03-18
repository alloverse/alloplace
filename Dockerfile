FROM elixir:1.7.4

WORKDIR /app

RUN apt-get update && apt-get install -y build-essential \
    cmake \
    clang-3.8 \
    git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ADD . /app/

RUN mix local.hex --force

RUN mix deps.get

RUN mix compile

CMD mix run --no-halt
