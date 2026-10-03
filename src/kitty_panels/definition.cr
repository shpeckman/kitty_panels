# src/kitty_panels/definition.cr
require "json"
require "yaml"
require "./wire"
require "./colors"

module KittyPanels
  class PanelDefinition
    include JSON::Serializable
    include YAML::Serializable

    record Field,
      key    : String,
      live   : Bool,
      switch : Bool,
      set    : Proc(PanelDefinition, String, Nil),
      render : Proc(PanelDefinition, String?) do
      def flag : String
        key.tr("_", "-")
      end
    end

    macro choice(name, type, live = true)
      Field.new({{name.id.stringify}}, {{live}}, false,
        ->(d : PanelDefinition, v : String) { d.{{name.id}} = {{type}}.from_wire(v); nil },
        ->(d : PanelDefinition) { d.{{name.id}}.try(&.wire).as(String?) })
    end

    macro text(name, live = true)
      Field.new({{name.id.stringify}}, {{live}}, false,
        ->(d : PanelDefinition, v : String) { d.{{name.id}} = v; nil },
        ->(d : PanelDefinition) { d.{{name.id}}.presence.as(String?) })
    end

    macro integer(name)
      Field.new({{name.id.stringify}}, true, false,
        ->(d : PanelDefinition, v : String) { d.{{name.id}} = PanelDefinition.parse_int({{name.id.stringify}}, v); nil },
        ->(d : PanelDefinition) { d.{{name.id}}.try(&.to_s).as(String?) })
    end

    macro switch(name, live = true)
      Field.new({{name.id.stringify}}, {{live}}, true,
        ->(d : PanelDefinition, v : String) { d.{{name.id}} = PanelDefinition.parse_bool({{name.id.stringify}}, v); nil },
        ->(d : PanelDefinition) { (d.{{name.id}} ? "" : nil).as(String?) })
    end

    macro pair(name)
      Field.new({{name.id.stringify}}, false, false,
        ->(d : PanelDefinition, v : String) { d.add_{{name.id}}(v); nil },
        ->(d : PanelDefinition) { nil.as(String?) })
    end

    BOOL_TRUE     = Set{"yes", "true", "1", "on"}
    BOOL_FALSE    = Set{"no", "false", "0", "off"}
    NAME_RE       = /\A[a-zA-Z0-9_-]+\z/
    SIZE_RE       = /\A\d+(px|c)?\z/
    OPACITY_RANGE = 0.0..1.0

    enum OverrideKind
      Opacity
      Color
      Padding
      Margin
      Layouts
      Ligatures
      BackgroundImage
      ImageLayout
      WindowLogo
      LogoPosition
      LogoAlpha
    end

    record OverrideSpec, key : String, kind : OverrideKind

    COLOR_OPTIONS = Set{
      "foreground", "background", "selection_foreground", "selection_background",
      "cursor", "cursor_text_color", "url_color", "visual_bell_color",
      "active_border_color", "inactive_border_color", "bell_border_color",
      "wayland_titlebar_color", "macos_titlebar_color",
      "active_tab_foreground", "active_tab_background",
      "inactive_tab_foreground", "inactive_tab_background",
      "tab_bar_background", "tab_bar_margin_color",
      "mark1_foreground", "mark1_background", "mark2_foreground", "mark2_background",
      "mark3_foreground", "mark3_background",
    }
    COLOR_OPTION_RE = /\Acolor(\d{1,3})\z/
    LIGATURE_VALUES = Set{"never", "always", "cursor"}
    IMAGE_LAYOUTS   = Set{"configured", "tiled", "mirror-tiled", "scaled", "clamped", "centered", "cscaled"}

    OVERRIDE_SPECS = [
      OverrideSpec.new("background_opacity", OverrideKind::Opacity),
      OverrideSpec.new("window_padding_width", OverrideKind::Padding),
      OverrideSpec.new("window_margin_width", OverrideKind::Margin),
      OverrideSpec.new("enabled_layouts", OverrideKind::Layouts),
      OverrideSpec.new("ligatures", OverrideKind::Ligatures),
      OverrideSpec.new("background_image", OverrideKind::BackgroundImage),
      OverrideSpec.new("background_image_layout", OverrideKind::ImageLayout),
      OverrideSpec.new("window_logo", OverrideKind::WindowLogo),
      OverrideSpec.new("window_logo_position", OverrideKind::LogoPosition),
      OverrideSpec.new("window_logo_alpha", OverrideKind::LogoAlpha),
    ]
    OVERRIDE_BY_KEY = OVERRIDE_SPECS.to_h { |spec| {spec.key, spec} }

    FIELDS = [
      choice(edge, Edge),
      choice(layer, Layer),
      text(lines),
      text(columns),
      integer(margin_top),
      integer(margin_bottom),
      integer(margin_left),
      integer(margin_right),
      choice(focus_policy, FocusPolicy),
      text(output_name),
      integer(exclusive_zone),
      switch(override_exclusive_zone),
      switch(hide_on_focus_loss),
      choice(mode, Mode, false),
      text(app_id, false),
      pair(env),
      pair(kitty_override),
    ]

    FIELD_BY_KEY      = FIELDS.to_h { |field| {field.key, field} }
    CONFIGURABLE_KEYS = FIELDS.select(&.live).map(&.key).to_set

    property name                    : String               = ""
    property edge                    : Edge                 = Edge::Top
    property layer                   : Layer                = Layer::Top
    property lines                   : String               = "25"
    property columns                 : String               = ""
    property margin_top              : Int32                = 0
    property margin_bottom           : Int32                = 0
    property margin_left             : Int32                = 0
    property margin_right            : Int32                = 0
    property focus_policy            : FocusPolicy          = FocusPolicy::OnDemand
    property output_name             : String               = ""
    property exclusive_zone          : Int32?               = nil
    property override_exclusive_zone : Bool                 = false
    property hide_on_focus_loss      : Bool                 = false
    property mode                    : Mode                 = Mode::Dropdown
    property app_id                  : String               = "kitty-panels"
    property cmd                     : Array(String)        = [] of String
    property env                     : Hash(String, String) = {} of String => String
    property kitty_overrides         : Hash(String, String) = {} of String => String

    def initialize(@name : String)
    end

    def self.parse_int(key : String, value : String) : Int32
      value.to_i32? || raise(ArgumentError.new("setting '#{key}' expects an integer, got '#{value}'"))
    end

    def self.parse_bool(key : String, value : String) : Bool
      downcased = value.downcase
      return true if BOOL_TRUE.includes?(downcased)
      return false if BOOL_FALSE.includes?(downcased)
      raise ArgumentError.new("setting '#{key}' expects a boolean, got '#{value}'")
    end

    def validate! : Nil
      raise ArgumentError.new("panel name '#{@name}' is invalid, use letters, digits, '-' and '_'") unless @name =~ NAME_RE
      validate_settings!
      raise ArgumentError.new("panel '#{@name}' has no command to run") if @cmd.empty?
    end

    def validate_settings! : Nil
      raise ArgumentError.new("invalid lines '#{@lines}', expected e.g. 25, 200px or 10c") unless @lines.empty? || @lines =~ SIZE_RE
      raise ArgumentError.new("invalid columns '#{@columns}', expected e.g. 80, 400px or 20c") unless @columns.empty? || @columns =~ SIZE_RE
      @kitty_overrides.each { |key, value| PanelDefinition.validate_override(key, value) }
      if (@kitty_overrides.has_key?("window_logo_position") || @kitty_overrides.has_key?("window_logo_alpha")) && !@kitty_overrides.has_key?("window_logo")
        raise ArgumentError.new("window_logo_position and window_logo_alpha require window_logo")
      end
      if @kitty_overrides.has_key?("background_image_layout") && !@kitty_overrides.has_key?("background_image")
        raise ArgumentError.new("background_image_layout requires background_image")
      end
    end

    def self.override_kind(key : String) : OverrideKind
      return OverrideKind::Color if color_key?(key)
      OVERRIDE_BY_KEY[key]?.try(&.kind) || raise ArgumentError.new(
        "kitty_override '#{key}' cannot be applied per panel, expected one of #{OVERRIDE_BY_KEY.keys.join(", ")} or a kitty color option")
    end

    def self.color_key?(key : String) : Bool
      return true if COLOR_OPTIONS.includes?(key)
      if match = key.match(COLOR_OPTION_RE)
        return match[1].to_i <= 255
      end
      false
    end

    def self.validate_override(key : String, value : String) : Nil
      case override_kind(key)
      in .opacity?           then validate_number(key, value, OPACITY_RANGE)
      in .color?             then Colors.parse(value); nil
      in .padding?, .margin? then validate_number(key, value, nil)
      in .layouts?           then validate_layouts(value)
      in .ligatures?
        unless LIGATURE_VALUES.includes?(value)
          raise ArgumentError.new("invalid ligatures '#{value}', expected never, always or cursor")
        end
      in .image_layout?
        unless IMAGE_LAYOUTS.includes?(value)
          raise ArgumentError.new("invalid background_image_layout '#{value}', expected one of #{IMAGE_LAYOUTS.join(", ")}")
        end
      in .logo_alpha?                                       then validate_number(key, value, OPACITY_RANGE)
      in .background_image?, .window_logo?, .logo_position? then nil
      end
    end

    def self.validate_number(key : String, value : String, range : Range(Float64, Float64)?) : Nil
      number = value.to_f64? || raise ArgumentError.new("invalid #{key} '#{value}', expected a number")
      if range && !range.includes?(number)
        raise ArgumentError.new("invalid #{key} '#{value}', expected a number between #{range.begin} and #{range.end}")
      end
    end

    def self.validate_layouts(value : String) : Nil
      names = value.split(',').map(&.strip)
      if names.empty? || names.any?(&.empty?)
        raise ArgumentError.new("invalid enabled_layouts '#{value}', expected a comma-separated list of layouts")
      end
    end

    def clone : PanelDefinition
      PanelDefinition.from_json(to_json)
    end

    def apply(key : String, value : String) : Nil
      field = FIELD_BY_KEY[key]? || raise ArgumentError.new("unknown panel setting '#{key}'")
      field.set.call(self, value)
    end

    def add_env(pair : String) : Nil
      key, separator, value = pair.partition('=')
      raise ArgumentError.new("env expects KEY=VALUE, got '#{pair}'") if key.empty? || separator.empty?
      @env[key] = value
    end

    def add_kitty_override(pair : String) : Nil
      key, separator, value = pair.partition('=')
      raise ArgumentError.new("kitty_override expects NAME=VALUE, got '#{pair}'") if key.empty? || separator.empty?
      @kitty_overrides[key] = value
    end

    def to_os_panel_args(only : Set(String)? = nil) : Array(String)
      FIELDS.compact_map do |field|
        next unless field.live && (only.nil? || only.includes?(field.key))
        value = field.render.call(self) || next
        field.switch ? field.flag : "#{field.flag}=#{value}"
      end
    end

    def with_settings(settings : Hash(String, String)) : PanelDefinition
      candidate = clone
      settings.each do |key, value|
        field = FIELD_BY_KEY[key]?
        unless field && field.live
          raise ArgumentError.new("setting '#{key}' cannot be reconfigured on a live panel, recreate it instead")
        end
        if value.empty?
          raise ArgumentError.new("setting '#{key}' cannot be cleared on a live panel, recreate the panel without it")
        end
        if field.switch && !BOOL_TRUE.includes?(value.downcase)
          raise ArgumentError.new("setting '#{key}' can only be switched on via configure, recreate the panel to switch it off")
        end
        field.set.call(candidate, value)
      end
      candidate.validate_settings!
      candidate
    end
  end
end
