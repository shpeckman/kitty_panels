# src/kitty_panels/rc/commands.cr
require "base64"
require "../rc"

class KittyPanels::RC
  TEXT_EXTENTS     = Set{"screen", "first_cmd_output_on_screen", "last_cmd_output", "last_visited_cmd_output", "last_non_empty_output", "all", "selection", "alternate", "alternate_scrollback"}
  RESIZE_ACTIONS   = Set{"resize", "toggle-fullscreen", "toggle-maximized", "toggle-visibility", "hide", "show", "os-panel"}
  RESIZE_UNITS     = Set{"cells", "pixels"}
  RESIZE_AXES      = Set{"horizontal", "vertical", "reset"}
  LIGATURE_MODES   = Set{"never", "always", "cursor"}
  BRACKETED_PASTES = Set{"disable", "auto", "enable"}
  LS_FORMATS       = Set{"json", "session"}
  WINDOW_TYPES     = Set{"kitty", "os"}

  COMMAND_NAMES = Set{
    "action", "close-tab", "close-window", "create-marker", "detach-tab",
    "detach-window", "disable-ligatures", "env", "focus-tab", "focus-window",
    "get-colors", "get-text", "goto-layout", "kitten", "last-used-layout",
    "launch", "load-config", "ls", "new-window", "remove-marker",
    "resize-os-window", "resize-window", "run", "screenshot", "scroll-window",
    "select-window", "send-key", "send-text", "set-background-image",
    "set-background-opacity", "set-colors", "set-enabled-layouts",
    "set-font-size", "set-os-window-title", "set-spacing", "set-tab-color",
    "set-tab-title", "set-user-vars", "set-window-logo", "set-window-title",
    "signal-child",
  }

  def action(action : String, *, match_window : String? = nil, self_ : Bool = false) : Nil
    command("action", build_payload({action: action, match_window: match_window, self_: self_}))
    nil
  end

  def close_tab(*, match : String? = nil, self_ : Bool = false, ignore_no_match : Bool = false) : Nil
    command("close-tab", build_payload({match: match, self_: self_, ignore_no_match: ignore_no_match}))
    nil
  end

  def close_window(*, match : String? = nil, self_ : Bool = false, ignore_no_match : Bool = false) : Nil
    command("close-window", build_payload({match: match, self_: self_, ignore_no_match: ignore_no_match}))
    nil
  end

  def create_marker(*, match : String? = nil, self_ : Bool = false, marker_spec : Array(String)? = nil) : Nil
    command("create-marker", build_payload({match: match, self_: self_, marker_spec: marker_spec}))
    nil
  end

  def detach_tab(*, match : String? = nil, target_tab : String? = nil, self_ : Bool = false) : Nil
    command("detach-tab", build_payload({match: match, target_tab: target_tab, self_: self_}))
    nil
  end

  def detach_window(*, match : String? = nil, target_tab : String? = nil, self_ : Bool = false, stay_in_tab : Bool = false) : Nil
    command("detach-window", build_payload({match: match, target_tab: target_tab, self_: self_, stay_in_tab: stay_in_tab}))
    nil
  end

  def disable_ligatures(strategy : String, *, match_window : String? = nil, match_tab : String? = nil, all : Bool = false) : Nil
    raise RCError.new("invalid ligature strategy '#{strategy}'") unless LIGATURE_MODES.includes?(strategy)
    command("disable-ligatures", build_payload({strategy: strategy, match_window: match_window, match_tab: match_tab, all: all}))
    nil
  end

  def env(vars : Hash(String, String)) : Nil
    command("env", build_payload({env: vars}))
    nil
  end

  def focus_tab(*, match : String? = nil) : Nil
    command("focus-tab", build_payload({match: match}))
    nil
  end

  def focus_window(*, match : String? = nil) : Nil
    command("focus-window", build_payload({match: match}))
    nil
  end

  def get_colors(*, match : String? = nil, configured : Bool = false) : JSON::Any
    data = command("get-colors", build_payload({match: match, configured: configured}))["data"]?
    parse_json_data(data)
  end

  def get_text(*, match : String? = nil, extent : String = "screen", ansi : Bool = false, cursor : Bool = false, wrap_markers : Bool = false, clear_selection : Bool = false, self_ : Bool = false) : String
    raise RCError.new("invalid extent '#{extent}'") unless TEXT_EXTENTS.includes?(extent)
    command("get-text", build_payload({match: match, extent: extent, ansi: ansi, cursor: cursor, wrap_markers: wrap_markers, clear_selection: clear_selection, self_: self_}))["data"]?.try(&.as_s?) || ""
  end

  def goto_layout(layout : String, *, match : String? = nil) : Nil
    command("goto-layout", build_payload({layout: layout, match: match}))
    nil
  end

  def kitten(name : String, args : Array(String) = [] of String, *, match : String? = nil) : Nil
    command("kitten", build_payload({kitten: name, args: args, match: match}))
    nil
  end

  def last_used_layout(*, match : String? = nil, all : Bool = false) : Nil
    command("last-used-layout", build_payload({match: match, all: all}))
    nil
  end

  def launch(args                        : Array(String), *,
             type                        : String         = "window",
             match                       : String?        = nil,
             os_panel                    : Array(String)? = nil,
             env                         : Array(String)? = nil,
             var                         : Array(String)? = nil,
             window_title                : String?        = nil,
             os_window_name              : String?        = nil,
             os_window_class             : String?        = nil,
             os_window_title             : String?        = nil,
             os_window_state             : String?        = nil,
             os_window_position          : String?        = nil,
             keep_focus                  : Bool           = false,
             copy_colors                 : Bool           = false,
             copy_cmdline                : Bool           = false,
             copy_env                    : Array(String)? = nil,
             cwd                         : String?        = nil,
             hold                        : Bool           = false,
             hold_after_ssh              : Bool           = false,
             location                    : String?        = nil,
             next_to                     : String?        = nil,
             source_window               : String?        = nil,
             tab_title                   : String?        = nil,
             add_to_session              : String?        = nil,
             allow_remote_control        : Bool           = false,
             remote_control_password     : Array(String)? = nil,
             stdin_source                : String?        = nil,
             stdin_add_formatting        : Bool           = false,
             stdin_add_line_wrap_markers : Bool           = false,
             spacing                     : Array(String)? = nil,
             marker                      : String?        = nil,
             logo                        : String?        = nil,
             logo_position               : String?        = nil,
             logo_alpha                  : Float64?       = nil,
             color                       : Array(String)? = nil,
             watcher                     : Array(String)? = nil,
             bias                        : Float64?       = nil,
             wait_for_child_to_exit      : Bool           = false,
             self_                       : Bool           = false,
             timeout                     : Time::Span     = DEFAULT_TIMEOUT) : String
    payload = build_payload({
      args: args, type: type, match: match, os_panel: os_panel, env: env, var: var,
      window_title: window_title, os_window_name: os_window_name, os_window_class: os_window_class,
      os_window_title: os_window_title, os_window_state: os_window_state, os_window_position: os_window_position,
      keep_focus: keep_focus, copy_colors: copy_colors, copy_cmdline: copy_cmdline, copy_env: copy_env,
      cwd: cwd, hold: hold, hold_after_ssh: hold_after_ssh, location: location, next_to: next_to,
      source_window: source_window, tab_title: tab_title, add_to_session: add_to_session,
      allow_remote_control: allow_remote_control, remote_control_password: remote_control_password,
      stdin_source: stdin_source, stdin_add_formatting: stdin_add_formatting,
      stdin_add_line_wrap_markers: stdin_add_line_wrap_markers, spacing: spacing, marker: marker,
      logo: logo, logo_position: logo_position, logo_alpha: logo_alpha, color: color,
      watcher: watcher, bias: bias, wait_for_child_to_exit: wait_for_child_to_exit, self_: self_,
    })
    resp = wait_for_child_to_exit ? command_async("launch", payload, timeout: timeout) : command("launch", payload, timeout: timeout)
    resp["data"]?.try(&.as_s?) || ""
  end

  def load_config(*, paths : Array(String)? = nil, overrides : Array(String)? = nil, ignore_overrides : Bool = false) : Nil
    command("load-config", build_payload({paths: paths, overrides: overrides, ignore_overrides: ignore_overrides}))
    nil
  end

  def ls(*, match : String? = nil, match_tab : String? = nil, all_env_vars : Bool = false, output_format : String = "json", self_ : Bool = false) : JSON::Any
    raise RCError.new("invalid ls output_format '#{output_format}'") unless LS_FORMATS.includes?(output_format)
    data = command("ls", build_payload({match: match, match_tab: match_tab, all_env_vars: all_env_vars, output_format: output_format, self_: self_}))["data"]?
    return JSON::Any.new(nil) unless data
    return data unless output_format == "json"
    parse_json_data(data)
  end

  def new_window(args : Array(String), *, match : String? = nil, title : String? = nil, cwd : String? = nil, keep_focus : Bool = false, window_type : String = "kitty", new_tab : Bool = false, tab_title : String? = nil) : Nil
    raise RCError.new("invalid window_type '#{window_type}'") unless WINDOW_TYPES.includes?(window_type)
    command("new-window", build_payload({args: args, match: match, title: title, cwd: cwd, keep_focus: keep_focus, window_type: window_type, new_tab: new_tab, tab_title: tab_title}))
    nil
  end

  def remove_marker(*, match : String? = nil, self_ : Bool = false) : Nil
    command("remove-marker", build_payload({match: match, self_: self_}))
    nil
  end

  def resize_os_window(*, match : String? = nil, action : String = "resize", unit : String = "cells", width : Int32 = 0, height : Int32 = 0, incremental : Bool = false, os_panel : Array(String)? = nil, self_ : Bool = false) : Nil
    raise RCError.new("invalid resize-os-window action '#{action}'") unless RESIZE_ACTIONS.includes?(action)
    raise RCError.new("invalid resize unit '#{unit}'") unless RESIZE_UNITS.includes?(unit)
    command("resize-os-window", build_payload({match: match, action: action, unit: unit, width: width, height: height, incremental: incremental, os_panel: os_panel, self_: self_}))
    nil
  end

  def resize_window(*, match : String? = nil, self_ : Bool = false, increment : Int32 = 2, axis : String = "horizontal") : Nil
    raise RCError.new("invalid resize axis '#{axis}'") unless RESIZE_AXES.includes?(axis)
    command("resize-window", build_payload({match: match, self_: self_, increment: increment, axis: axis}))
    nil
  end

  def run(cmdline : Array(String), *, stdin : Bytes = Bytes.empty, env : Array(String)? = nil, allow_remote_control : Bool = false, remote_control_password : Array(String)? = nil, timeout : Time::Span = DEFAULT_TIMEOUT) : JSON::Any
    raise RCError.new("run requires a command line") if cmdline.empty?
    payload = build_payload({cmdline: cmdline, env: env, allow_remote_control: allow_remote_control, remote_control_password: remote_control_password})
    command_stream("run", payload, base64_chunks(stdin, 3072), timeout: timeout)
  end

  def screenshot(*, match : String? = nil, match_tab : String? = nil, output_path : String? = nil) : JSON::Any
    data = command("screenshot", build_payload({match: match, match_tab: match_tab, output_path: output_path}))["data"]?
    data || JSON::Any.new(nil)
  end

  def scroll_window(amount : Int32 | String, unit : String = "l", *, match : String? = nil) : Nil
    command("scroll-window", build_payload({amount: [amount, unit], match: match}))
    nil
  end

  def select_window(*, match : String? = nil, self_ : Bool = false, title : String? = nil, exclude_active : Bool = false, reactivate_prev_tab : Bool = false, timeout : Time::Span = ASYNC_TIMEOUT, async_id : String = Random::Secure.hex(16)) : String
    command_async("select-window", build_payload({match: match, self_: self_, title: title, exclude_active: exclude_active, reactivate_prev_tab: reactivate_prev_tab}), timeout: timeout, async_id: async_id)["data"]?.try(&.as_s?) || ""
  end

  def send_key(keys : Array(String), *, match : String? = nil, match_tab : String? = nil, all : Bool = false, exclude_active : Bool = false) : Nil
    raise RCError.new("send-key requires at least one key") if keys.empty?
    command("send-key", build_payload({keys: keys, match: match, match_tab: match_tab, all: all, exclude_active: exclude_active}))
    nil
  end

  def send_text(*, data : String, match : String? = nil, match_tab : String? = nil, all : Bool = false, exclude_active : Bool = false, session_id : String? = nil, bracketed_paste : String = "disable") : Nil
    raise RCError.new("invalid bracketed_paste '#{bracketed_paste}'") unless BRACKETED_PASTES.includes?(bracketed_paste)
    command_no_response("send-text", build_payload({data: "text:#{data}", match: match, match_tab: match_tab, all: all, exclude_active: exclude_active, session_id: session_id, bracketed_paste: bracketed_paste}))
  end

  def send_text_encoded(*, data : String, match : String? = nil, match_tab : String? = nil, all : Bool = false, exclude_active : Bool = false, session_id : String? = nil, bracketed_paste : String = "disable") : Nil
    raise RCError.new("invalid bracketed_paste '#{bracketed_paste}'") unless BRACKETED_PASTES.includes?(bracketed_paste)
    raise RCError.new("encoded send-text data must start with text:, base64:, kitty-key: or session:") unless data =~ /\A(text|base64|kitty-key|session):/
    command_no_response("send-text", build_payload({data: data, match: match, match_tab: match_tab, all: all, exclude_active: exclude_active, session_id: session_id, bracketed_paste: bracketed_paste}))
  end

  def set_background_image(*, data : Bytes | String, match : String? = nil, layout : String = "configured", all : Bool = false, configured : Bool = false, timeout : Time::Span = DEFAULT_TIMEOUT) : Nil
    payload = build_payload({match: match, layout: layout, all: all, configured: configured})
    case data
    in String
      raise RCError.new(%(invalid background image directive '#{data}', expected "-" or "index:N")) unless data == "-" || data.starts_with?("index:")
      payload["data"] = J.s(data)
      command("set-background-image", payload, timeout: timeout)
    in Bytes
      command_stream("set-background-image", payload, base64_chunks(data, 384), timeout: timeout)
    end
    nil
  end

  def set_background_opacity(opacity : Float64, *, match_window : String? = nil, match_tab : String? = nil, all : Bool = false, toggle : Bool = false) : Nil
    command("set-background-opacity", build_payload({opacity: opacity, match_window: match_window, match_tab: match_tab, all: all, toggle: toggle}))
    nil
  end

  def set_colors(colors : Hash(String, Int32?) | String, *, match_window : String? = nil, match_tab : String? = nil, all : Bool = false, configured : Bool = false, reset : Bool = false) : Nil
    command("set-colors", build_payload({colors: colors, match_window: match_window, match_tab: match_tab, all: all, configured: configured, reset: reset}))
    nil
  end

  def set_enabled_layouts(layouts : Array(String), *, match : String? = nil, configured : Bool = false) : Nil
    command("set-enabled-layouts", build_payload({layouts: layouts, match: match, configured: configured}))
    nil
  end

  def set_font_size(size : Float64 = 0.0, *, all : Bool = false, increment_op : String? = nil) : Nil
    raise RCError.new("invalid increment_op '#{increment_op}'") if increment_op && !Set{"+", "-", "*", "/"}.includes?(increment_op)
    command("set-font-size", build_payload({size: size, all: all, increment_op: increment_op}))
    nil
  end

  def set_os_window_title(*, title : String? = nil, match : String? = nil) : Nil
    command("set-os-window-title", build_payload({title: title, match: match}))
    nil
  end

  def set_spacing(settings : Hash(String, Float64?), *, match_window : String? = nil, match_tab : String? = nil, all : Bool = false, configured : Bool = false) : Nil
    command("set-spacing", build_payload({settings: settings, match_window: match_window, match_tab: match_tab, all: all, configured: configured}))
    nil
  end

  def set_tab_color(colors : Hash(String, Int32?), *, match : String? = nil, self_ : Bool = false) : Nil
    command("set-tab-color", build_payload({colors: colors, match: match, self_: self_}))
    nil
  end

  def set_tab_title(title : String, *, match : String? = nil, self_ : Bool = false) : Nil
    command("set-tab-title", build_payload({title: title, match: match, self_: self_}))
    nil
  end

  def set_user_vars(vars : Array(String), *, match : String? = nil) : Nil
    command("set-user-vars", build_payload({var: vars, match: match}))
    nil
  end

  def set_window_logo(*, data : Bytes | String, position : String = "", alpha : Float64 = -1.0, match : String? = nil, self_ : Bool = false, timeout : Time::Span = DEFAULT_TIMEOUT) : Nil
    payload = build_payload({position: position, alpha: alpha, match: match, self_: self_})
    case data
    in String
      raise RCError.new(%(invalid window logo directive '#{data}', expected "-")) unless data == "-"
      payload["data"] = J.s(data)
      command("set-window-logo", payload, timeout: timeout)
    in Bytes
      command_stream("set-window-logo", payload, base64_chunks(data, 1536), timeout: timeout)
    end
    nil
  end

  def set_window_title(*, title : String? = nil, match : String? = nil, temporary : Bool = false) : Nil
    command("set-window-title", build_payload({title: title, match: match, temporary: temporary}))
    nil
  end

  def signal_child(signals : Array(String), *, match : String? = nil) : Nil
    raise RCError.new("no signals given") if signals.empty?
    command("signal-child", build_payload({signals: signals.map(&.upcase), match: match}))
    nil
  end

  private KEY_REMAP = {"self_" => "self", "overrides" => "override"}

  private def build_payload(opts : NamedTuple) : Hash(String, JSON::Any)
    result = {} of String => JSON::Any
    opts.each do |key, value|
      next if value.nil?
      result[KEY_REMAP[key.to_s]? || key.to_s] = JSON.parse(value.to_json)
    end
    result
  end

  private def parse_json_data(data : JSON::Any?) : JSON::Any
    return JSON::Any.new(nil) unless data
    raw = data.as_s? || return data
    JSON.parse(raw)
  rescue ex : JSON::ParseException
    raise RCError.new("malformed data from kitty: #{ex.message}")
  end

  private def base64_chunks(data : Bytes, raw_chunk_size : Int32) : Array(String)
    chunks = [] of String
    offset = 0
    while offset < data.size
      width = Math.min(raw_chunk_size, data.size - offset)
      chunks << Base64.strict_encode(String.new(data[offset, width]))
      offset += width
    end
    chunks
  end
end
