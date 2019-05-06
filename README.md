# Alloverse Placeserv

Server component of Alloverse. Basically a multiplayer game server, but for window manager-y
things.

## Setup 

### macOS
* `brew install elixir cmake`
* `mix deps.get`

### Ubuntu (including Ubuntu-on-Windows)

* `wget https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb `
* `sudo dpkg -i erlang-solutions_1.0_all.deb; rm erlang-solutions_1.0_all.deb`
* `sudo apt-get update`
* `sudo apt-get install esl-erlang`
* `sudo apt-get install elixir cmake clang`
* `mix deps.get`

## Run

* `mix run --no-halt`
