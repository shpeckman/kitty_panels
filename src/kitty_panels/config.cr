# src/kitty_panels/config.cr
require "yaml"
require "./definition"

module KittyPanels
  def self.load_definitions(path : String) : Array(PanelDefinition)
    content = ::File.read(path)
    return [] of PanelDefinition if content.strip.empty?
    panel_nodes(path, content).map do |name, node|
      begin
        defn = PanelDefinition.new(YAML::ParseContext.new, node)
        defn.name = name
        defn.validate!
        defn
      rescue ex : ArgumentError | YAML::ParseException
        raise ArgumentError.new("#{path}: panel '#{name}': #{ex.message}")
      end
    end
  end

  private def self.panel_nodes(path : String, content : String) : Array({String, YAML::Nodes::Node})
    root = YAML::Nodes.parse(content).nodes.first?
    raise ArgumentError.new("#{path}: expected a mapping with a 'panels' key") unless root.is_a?(YAML::Nodes::Mapping)
    panels = mapping_entries(root).find { |key, _| key == "panels" }.try(&.[1])
    return [] of {String, YAML::Nodes::Node} if panels.nil? || (panels.is_a?(YAML::Nodes::Scalar) && panels.value.empty?)
    raise ArgumentError.new("#{path}: 'panels' must map panel names to definitions") unless panels.is_a?(YAML::Nodes::Mapping)
    mapping_entries(panels)
  rescue ex : YAML::ParseException
    raise ArgumentError.new("#{path}: #{ex.message}")
  end

  private def self.mapping_entries(mapping : YAML::Nodes::Mapping) : Array({String, YAML::Nodes::Node})
    mapping.nodes.each_slice(2).compact_map do |(key, value)|
      key.is_a?(YAML::Nodes::Scalar) ? {key.value, value} : nil
    end.to_a
  end
end
