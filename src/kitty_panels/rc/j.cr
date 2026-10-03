# src/kitty_panels/rc/j.cr
require "json"

module KittyPanels
  module J
    extend self

    def obj(h : Hash(String, JSON::Any)) : JSON::Any
      JSON::Any.new(h)
    end

    def arr(a : Array(JSON::Any)) : JSON::Any
      JSON::Any.new(a)
    end

    def s(v : String) : JSON::Any
      JSON::Any.new(v)
    end

    def i(v : Int) : JSON::Any
      JSON::Any.new(v.to_i64)
    end

    def f(v : Float) : JSON::Any
      JSON::Any.new(v.to_f64)
    end

    def b(v : Bool) : JSON::Any
      JSON::Any.new(v)
    end

    def strs(a : Array(String)) : JSON::Any
      arr(a.map { |x| s(x) })
    end
  end
end
