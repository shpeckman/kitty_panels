# src/kitty_panels.cr
require "./kitty_panels/error"
require "./kitty_panels/wire"
require "./kitty_panels/colors"
require "./kitty_panels/definition"
require "./kitty_panels/timing"
require "./kitty_panels/rc"
require "./kitty_panels/engine"
require "./kitty_panels/config"

module KittyPanels
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end
