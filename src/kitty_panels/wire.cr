# src/kitty_panels/wire.cr
require "json"
require "yaml"

module KittyPanels
  module Wire
    macro define(name, *members)
      enum {{name}}
        {% for member in members %}
          {{member.id}}
        {% end %}

        def self.label : String
          {{name.id.stringify.underscore}}
        end

        def wire : String
          to_s.underscore.tr("_", "-")
        end

        def self.wires : Array(String)
          values.map(&.wire)
        end

        def self.from_wire?(text : String) : self?
          values.find { |value| value.wire == text }
        end

        def self.from_wire(text : String) : self
          from_wire?(text) || raise ArgumentError.new("invalid #{label} '#{text}', expected one of #{wires.join(", ")}")
        end

        def self.new(pull : JSON::PullParser) : self
          location = pull.location
          text     = pull.read_string
          from_wire?(text) || raise JSON::ParseException.new("invalid #{label} '#{text}'", *location)
        end

        def self.new(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : self
          node.raise "expected a scalar for #{label}" unless node.is_a?(YAML::Nodes::Scalar)
          from_wire?(node.value) || node.raise "invalid #{label} '#{node.value}'"
        end

        def to_json(json : JSON::Builder) : Nil
          json.string(wire)
        end

        def to_yaml(yaml : YAML::Nodes::Builder) : Nil
          yaml.scalar(wire)
        end
      end
    end
  end

  Wire.define Edge, Top, Bottom, Left, Right, Center, None, Background, CenterSized
  Wire.define Layer, Background, Bottom, Top, Overlay
  Wire.define FocusPolicy, NotAllowed, Exclusive, OnDemand
  Wire.define Mode, Dock, Dropdown, Overlay
end
