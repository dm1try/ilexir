# Ilexir [![Build Status](https://travis-ci.org/dm1try/ilexir.svg?branch=master)](https://travis-ci.org/dm1try/ilexir)

## Requirements
  - Neovim >= 1.6-dev
  - [Elixir host](https://github.com/dm1try/nvim#installation)

## Install
1. Add plug to nvim runtime.
2. Run `UpdateElixirPlugins` command.
3. Restart neovim.

## Features

Demo is coming soon.

![image](/images/src.png?raw=true)

## Development
```elixir
                             +                 +---------------------+
                             |             +--->  HOSTED COMPONENTS  +--------+
                             |             |   +---------------------+        |
      nvim + elixir host     |             |      |  compiler     |           |
                             |             |      +---------------+           |
  +----------------------+   |             |      |  linters      |           |
  |           |          |   |             |      +---------------+           |
  | +-----    | +----+   |   |             |      |  evaluator    |           |
  | |-------+ | +------+ |   |             |      +---------------+           |
  | |----|    |          |   |             |      |  ...          |           |
  | |----|    | +-----+  |   |             |      +---------------+           |
  | |-------+ | |------+ |   |             |                                  |
  | +-------+ | +----+   |   |    +------------------+  rpc  +----------------v-------+
  |           |          |   |    |       CORE       <------->    NODES(app & hosted) |
  +----------------------+   |    +------------------+       +------------------------+
  | +----+               |   |      |  hosted app  |            |  app1.dev        |
  |                      |   |      |   manager    |            +------------------+
  +----------------------+   |      +--------------+            +------------------+
                             |      | nvim specific|            |  app1.test       |
                             |      |  components: |            +------------------+
                             |      | +----------+ |            +------------------+
                             |      | | quickfix | |            |  umbrella1.dev   |
                             |      | +----------+ |            +------------------+
                             |      | | toolwin  | |            +------------------+
                             |      | +----------+ |            |  ...             |
                             |      +--------------+            +------------------+
                             |
                             +


```

