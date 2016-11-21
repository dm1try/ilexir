# Ilexir [![Build Status](https://travis-ci.org/dm1try/ilexir.svg?branch=master)](https://travis-ci.org/dm1try/ilexir)
## Requirements
  - Neovim >= 1.6-dev
  - [Elixir host](https://github.com/dm1try/nvim#installation)
  
> Windows platform is not supported.

## Install
1. Add the plugin to vim runtime.                                                                                                                             
>vim-plug example: `Plug 'dm1try/ilexir'`
    
2. Run `UpdateElixirPlugins` command.
3. Restart the editor.

## Usage
  > On the way: Take a look at this asciinema demo for a quick start.
  
### Common commands:
  - `IlexirStartApp /path/to/app` - runs a hosted app in the specified directory.
  -  `IlexirStartInWorkingDir` - the shortcut for running in current working directory.  
     Available options:
     - `env` - app enviroment *(default "dev")*                           
     - `script` - start script for mix apps *(default "app.start")*  

 > IlexirStartInWorkingDir --env dev --script phoenix.server
    
    
  - `IlexirOpenIex` - opens IEx for a running app.
  - `IlexirEval` - evals selected lines.
  
### Editor settings
  `ilexir_autocompile` - `1`(default) or `0`, enable/disable auto compiling.
  The file can be compiled manually by `IlexirCompile` command. See the architecture section for details.
  > Changes for this var are applied in runtime `:let ilexir_autocompile = 0`
  
## Features
 - "smart" omni completion
 
 ![autocomplete](https://cloud.githubusercontent.com/assets/486807/20452668/8cfb84aa-ae20-11e6-94f3-3cbb9a6dfbce.gif)
 
 - "on-the-fly" linters
  - ast (it validates the AST:) it's only usefull if autocompilation is disabled)
  - compiler (compiler errors and warnings must be fixed ASAP)
  - xref (it validates the runtime code for unreachable module/functions)
  
 ![linters](https://cloud.githubusercontent.com/assets/486807/20470386/2c357f46-afb9-11e6-8661-4ecd6078ef76.gif)

 - app integration
  - iex shell(stdio is piped to a separated buffer)
  - multiple applications support

 - "live" evaluation

 - jump to definition

 - open online documentation
  - for elixir packages using hexdocs.pm(respects the package version)
  - for Elixir core
  - for erlang stdlib

 - core components are editor agnostic

## Development 
### Architecture
"Hosted" app is your app that is bootstrapped with bunch of hosted components. The app is running on remote erlang node.
> In case you are playing around with a simple script outside of any app,             
>  it will be just a node with running `elixir` on it. See the demo above.

The hosted components work inside your running app enviroment, so they can inspect the app and provide the data on demand to "editor-specific" components. They talk to each other through `:rpc` module.


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

Elixir core building blocks(`def/defmodule/alias/use/import`) are macros that are applied directly to AST so the provided solution is "compile-first". The information provided by plugin components will be a more "accurate" if a working file is processed by the Ilexir compiler. The compiler pre-saves(in memory) useful data between compilations(such as __ENV__ module struct) and also notifies other components during/after the compilation that they can handle the data for their own needs.

### Setup locally
Clone the repo and add it to neovim runtime.
> vim-plug example: `Plug '/home/user/Projects/ilexir'`

`ElixirHostLog` and `ElixirReloadScript` are useful [Elixir host](https://github.com/dm1try/nvim#installation) commands for a playing with local changes.

### Testing
Run tests:
  `mix espec`
### Writing components
> Coming soon
