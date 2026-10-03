# spec/unit/definition_spec.cr
require "../spec_helper"

private def definition(name = "panel", cmd = ["/bin/sh"]) : KittyPanels::PanelDefinition
  KittyPanels::PanelDefinition.new(name).tap { |defn| defn.cmd = cmd }
end

describe KittyPanels::PanelDefinition do
  describe "#validate!" do
    it "accepts the defaults with a command" do
      definition.validate!
    end

    {
      "bad name"      => ->(d : KittyPanels::PanelDefinition) { d.name = "has space" },
      "lines"         => ->(d : KittyPanels::PanelDefinition) { d.lines = "10em" },
      "columns"       => ->(d : KittyPanels::PanelDefinition) { d.columns = "-4" },
      "empty command" => ->(d : KittyPanels::PanelDefinition) { d.cmd = [] of String },
    }.each do |label, mutate|
      it "rejects an invalid #{label}" do
        defn = definition
        mutate.call(defn)
        expect_raises(ArgumentError) { defn.validate! }
      end
    end

    it "accepts a background opacity between 0 and 1" do
      {"0", "0.85", "1"}.each do |value|
        defn = definition
        defn.kitty_overrides["background_opacity"] = value
        defn.validate!
      end
    end

    it "accepts every kitty override that can be applied per panel" do
      defn = definition
      defn.kitty_overrides["background_opacity"] = "0.8"
      defn.kitty_overrides["background"] = "#112233"
      defn.kitty_overrides["foreground"] = "white"
      defn.kitty_overrides["color1"] = "red"
      defn.kitty_overrides["color255"] = "#aabbcc"
      defn.kitty_overrides["selection_background"] = "none"
      defn.kitty_overrides["window_padding_width"] = "12"
      defn.kitty_overrides["window_margin_width"] = "4.5"
      defn.kitty_overrides["enabled_layouts"] = "tall,stack"
      defn.kitty_overrides["ligatures"] = "never"
      defn.kitty_overrides["background_image"] = "/tmp/bg.png"
      defn.kitty_overrides["background_image_layout"] = "scaled"
      defn.kitty_overrides["window_logo"] = "/tmp/logo.png"
      defn.kitty_overrides["window_logo_position"] = "center"
      defn.kitty_overrides["window_logo_alpha"] = "0.5"
      defn.validate!
    end

    it "rejects unusable kitty overrides" do
      {
        {"background_opacity" => "abc"} => /invalid background_opacity/,
        {"background_opacity" => "1.5"} => /invalid background_opacity/,
        {"background_opacity" => "-0.1"} => /invalid background_opacity/,
        {"font_size" => "20"} => /cannot be applied per panel/,
        {"scrollback_lines" => "1000"} => /cannot be applied per panel/,
        {"background" => "octarine"} => /invalid color 'octarine'/,
        {"color7" => "12"} => /invalid color '12'/,
        {"color256" => "red"} => /cannot be applied per panel/,
        {"window_padding_width" => "wide"} => /invalid window_padding_width/,
        {"window_margin_width" => ""} => /invalid window_margin_width/,
        {"enabled_layouts" => "tall,,stack"} => /invalid enabled_layouts/,
        {"ligatures" => "sometimes"} => /invalid ligatures/,
        {"background_image_layout" => "wallpaper"} => /invalid background_image_layout/,
        {"window_logo_alpha" => "2"} => /invalid window_logo_alpha/,
        {"window_logo_position" => "center"} => /require window_logo/,
        {"background_image_layout" => "tiled"} => /requires background_image/,
      }.each do |overrides, message|
        defn = definition
        defn.kitty_overrides = overrides
        expect_raises(ArgumentError, message) { defn.validate! }
      end
    end

    it "accepts sizes in cells, pixels and character units" do
      {"25", "200px", "10c"}.each do |size|
        defn = definition
        defn.lines = size
        defn.columns = size
        defn.validate!
      end
    end
  end

  describe "#apply" do
    it "parses integers and booleans" do
      defn = definition
      defn.apply("margin_top", "12")
      defn.apply("exclusive_zone", "-1")
      defn.apply("hide_on_focus_loss", "Yes")
      defn.apply("override_exclusive_zone", "off")
      defn.margin_top.should eq(12)
      defn.exclusive_zone.should eq(-1)
      defn.hide_on_focus_loss.should be_true
      defn.override_exclusive_zone.should be_false
    end

    it "parses choices from their wire spelling" do
      defn = definition
      {
        "edge" => "center-sized", "layer" => "overlay", "focus_policy" => "not-allowed",
        "mode" => "dock",
      }.each { |key, value| defn.apply(key, value) }
      defn.edge.should eq(KittyPanels::Edge::CenterSized)
      defn.layer.should eq(KittyPanels::Layer::Overlay)
      defn.focus_policy.should eq(KittyPanels::FocusPolicy::NotAllowed)
      defn.mode.should eq(KittyPanels::Mode::Dock)
    end

    it "rejects unknown choices and names the valid ones" do
      defn = definition
      {
        "edge" => "diagonal", "layer" => "middle", "focus_policy" => "sometimes",
        "mode" => "floating",
      }.each do |key, value|
        error = expect_raises(ArgumentError, /invalid #{key} '#{value}'/) { defn.apply(key, value) }
        error.message.to_s.should contain("expected one of")
      end
      defn.to_json.should eq(definition.to_json)
    end

    it "rejects malformed integers, booleans and unknown keys" do
      defn = definition
      expect_raises(ArgumentError, /integer/) { defn.apply("margin_top", "wide") }
      expect_raises(ArgumentError, /boolean/) { defn.apply("hide_on_focus_loss", "perhaps") }
      expect_raises(ArgumentError, /unknown panel setting/) { defn.apply("colour", "red") }
    end

    it "collects env pairs and keeps '=' inside values" do
      defn = definition
      defn.apply("env", "A=1")
      defn.apply("env", "B=x=y")
      defn.apply("env", "EMPTY=")
      defn.env.should eq({"A" => "1", "B" => "x=y", "EMPTY" => ""})
      expect_raises(ArgumentError) { defn.apply("env", "NOVALUE") }
    end

    it "collects kitty overrides as NAME=VALUE pairs without judging the key" do
      defn = definition
      defn.apply("kitty_override", "background_opacity=0.5")
      defn.apply("kitty_override", "font_size=20")
      expect_raises(ArgumentError, /NAME=VALUE/) { defn.apply("kitty_override", "background_opacity") }
      defn.kitty_overrides.should eq({"background_opacity" => "0.5", "font_size" => "20"})
    end
  end

  describe "#to_os_panel_args" do
    it "restricts output to the requested keys" do
      definition.to_os_panel_args(Set{"lines", "edge"}).should eq(["edge=top", "lines=25"])
    end
  end

  describe "#with_settings" do
    it "returns a reconfigured copy and leaves the original alone" do
      defn = definition
      copy = defn.with_settings({"lines" => "10", "margin_top" => "3"})
      copy.lines.should eq("10")
      copy.margin_top.should eq(3)
      copy.cmd.should eq(defn.cmd)
      copy.to_os_panel_args(Set{"lines", "margin_top"}).should eq(["lines=10", "margin-top=3"])
      defn.lines.should eq("25")
      defn.margin_top.should eq(0)
    end

    it "rejects invalid values" do
      defn = definition
      {
        {"lines" => "not-a-size"} => /invalid lines/,
        {"columns" => "wide"} => /invalid columns/,
        {"edge" => "nowhere"} => /invalid edge/,
        {"layer" => "middle"} => /invalid layer/,
        {"focus_policy" => "sometimes"} => /invalid focus_policy/,
        {"margin_top" => "big"} => /integer/,
        {"lines" => "5", "edge" => "nowhere"} => /invalid edge/,
        {"lines" => "5", "margin_left" => "wide"} => /integer/,
      }.each do |settings, message|
        expect_raises(ArgumentError, message) { defn.with_settings(settings) }
      end
      defn.to_json.should eq(definition.to_json)
    end

    it "refuses to clear a setting" do
      {"columns", "lines", "output_name", "exclusive_zone"}.each do |key|
        expect_raises(ArgumentError, /'#{key}' cannot be cleared on a live panel/) { definition.with_settings({key => ""}) }
      end
    end

    it "works on a definition without a command" do
      KittyPanels::PanelDefinition.new("stray").with_settings({"lines" => "7"}).lines.should eq("7")
    end

    it "refuses keys that need a relaunch" do
      expect_raises(ArgumentError, /cannot be reconfigured/) { definition.with_settings({"mode" => "dock"}) }
    end

    it "refuses to switch boolean flags off" do
      expect_raises(ArgumentError, /only be switched on/) { definition.with_settings({"hide_on_focus_loss" => "no"}) }
    end
  end

  describe "#clone" do
    it "clones without sharing state" do
      old  = definition
      copy = old.clone
      copy.cmd << "extra"
      copy.env["K"] = "V"
      old.cmd.should eq(["/bin/sh"])
      old.env.should be_empty
    end
  end

  describe "field table" do
    it "covers every live kitty option exactly once" do
      keys = KittyPanels::PanelDefinition::FIELDS.map(&.key)
      keys.uniq.size.should eq(keys.size)
      KittyPanels::PanelDefinition::CONFIGURABLE_KEYS.should eq(Set{
        "edge", "layer", "lines", "columns", "margin_top", "margin_bottom", "margin_left", "margin_right",
        "focus_policy", "output_name", "exclusive_zone", "override_exclusive_zone", "hide_on_focus_loss",
      })
    end

    it "derives kitty flags from the key" do
      KittyPanels::PanelDefinition::FIELD_BY_KEY["margin_top"].flag.should eq("margin-top")
      KittyPanels::PanelDefinition::FIELD_BY_KEY["output_name"].flag.should eq("output-name")
    end

    it "sets every field through apply" do
      samples = {
        "edge" => "left", "layer" => "bottom", "lines" => "9", "columns" => "70", "margin_top" => "1",
        "margin_bottom" => "2", "margin_left" => "3", "margin_right" => "4", "focus_policy" => "exclusive",
        "output_name" => "DP-2", "exclusive_zone" => "12", "override_exclusive_zone" => "yes",
        "hide_on_focus_loss" => "yes", "mode" => "overlay", "app_id" => "custom",
      }
      fields = KittyPanels::PanelDefinition::FIELDS
      fields.map(&.key).sort!.should eq((samples.keys + ["env", "kitty_override"]).sort!)
      defn = definition
      samples.each { |key, value| defn.apply(key, value) }
      defn.to_os_panel_args.should eq([
        "edge=left", "layer=bottom", "lines=9", "columns=70", "margin-top=1", "margin-bottom=2",
        "margin-left=3", "margin-right=4", "focus-policy=exclusive", "output-name=DP-2",
        "exclusive-zone=12", "override-exclusive-zone", "hide-on-focus-loss",
      ])
      defn.mode.should eq(KittyPanels::Mode::Overlay)
      defn.app_id.should eq("custom")
    end
  end

  describe "serialization" do
    it "keeps the wire spellings in JSON" do
      defn = definition
      defn.edge = KittyPanels::Edge::CenterSized
      defn.focus_policy = KittyPanels::FocusPolicy::NotAllowed
      json = JSON.parse(defn.to_json)
      json["edge"].as_s.should eq("center-sized")
      json["focus_policy"].as_s.should eq("not-allowed")
      json["mode"].as_s.should eq("dropdown")
    end

    it "rejects an unknown choice in JSON" do
      expect_raises(JSON::ParseException, /invalid edge 'sideways'/) do
        KittyPanels::PanelDefinition.from_json(%({"name":"x","edge":"sideways"}))
      end
    end

    it "survives a JSON round trip" do
      defn = definition("round", ["/bin/sh", "-c", "echo hi"])
      defn.env["K"] = "V"
      defn.exclusive_zone = 30
      copy = KittyPanels::PanelDefinition.from_json(defn.to_json)
      copy.to_json.should eq(defn.to_json)
    end
  end
end
