# src/kitty_panels/version.cr
module KittyPanels
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end
