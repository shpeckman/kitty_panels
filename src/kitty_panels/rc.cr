# src/kitty_panels/rc.cr
require "socket"
require "json"
require "random/secure"
require "./rc/j"
require "./definition"
require "./rc/crypto"
require "./rc/commands"

module KittyPanels
  class RCError < Exception
  end

  class RC
    record LivePanel, os_window_id : Int64, window_id : Int64, focused : Bool

    RESPONSE_RE     = /\x1bP@kitty-cmd(.+?)\x1b\\/m
    KITTY_VERSION   = {0, 34, 0}
    DEFAULT_TIMEOUT = 15.seconds
    ASYNC_TIMEOUT   = 120.seconds
    PANEL_VAR       = "kitty_panels_name"
    PANEL_ENV_VAR   = "KITTY_PANELS_PANEL_NAME"

    def initialize(@socket_path : String, @password : String? = nil)
    end

    def self.panel_match(name : String) : String
      "var:#{PANEL_VAR}=#{name}"
    end

    def command(cmd : String, payload : Hash(String, JSON::Any) = {} of String => JSON::Any, timeout : Time::Span = DEFAULT_TIMEOUT) : JSON::Any
      extract_response(roundtrip(envelope(cmd, payload), timeout))
    end

    def command_no_response(cmd : String, payload : Hash(String, JSON::Any) = {} of String => JSON::Any) : Nil
      roundtrip(envelope(cmd, payload, no_response: true), DEFAULT_TIMEOUT, expect_response: false)
      nil
    end

    def command_async(cmd : String, payload : Hash(String, JSON::Any) = {} of String => JSON::Any, timeout : Time::Span = ASYNC_TIMEOUT, async_id : String = Random::Secure.hex(16)) : JSON::Any
      message = envelope(cmd, payload)
      message.as_h["async"] = J.s(async_id)
      extract_response(roundtrip(message, timeout))
    end

    def cancel_async(cmd : String, async_id : String) : Nil
      message = envelope(cmd, {} of String => JSON::Any, no_response: true)
      message.as_h["async"] = J.s(async_id)
      message.as_h["cancel_async"] = J.b(true)
      roundtrip(message, DEFAULT_TIMEOUT, expect_response: false)
      nil
    end

    def command_stream(cmd : String, payload : Hash(String, JSON::Any), chunks : Enumerable(String), timeout : Time::Span = DEFAULT_TIMEOUT) : JSON::Any
      list = chunks.to_a
      if list.size <= 1
        single = payload.dup
        single["data"] = J.s(list[0]? || "")
        return command(cmd, single, timeout: timeout)
      end
      stream_id = Random::Secure.hex(16)
      sock      = connect
      begin
        sock.read_timeout = timeout
        response : JSON::Any? = nil
        (list + [""]).each do |chunk|
          chunk_payload = payload.dup
          chunk_payload["data"] = J.s(chunk)
          message = envelope(cmd, chunk_payload)
          message.as_h["stream"] = J.b(true)
          message.as_h["stream_id"] = J.s(stream_id)
          sock.write(encode(message))
          sock.flush
          response = extract_response(read_frame(sock))
        end
        response || raise(RCError.new("streamed #{cmd} ended without a final response"))
      rescue ex : IO::TimeoutError
        raise RCError.new("timed out during streamed #{cmd} (socket: #{@socket_path})")
      ensure
        sock.close rescue nil
      end
    end

    def alive? : Bool
      command("ls")
      true
    rescue
      false
    end

    def ls : JSON::Any
      ls(output_format: "json")
    end

    def live_panels : Hash(String, LivePanel)
      result     = {} of String => LivePanel
      os_windows = ls.as_a? || return result
      os_windows.each do |osw|
        os_window_id = osw["id"].as_i64
        focused      = osw["is_focused"]?.try(&.as_bool?) || false
        tabs         = osw["tabs"]?.try(&.as_a) || next
        tabs.each do |tab|
          windows = tab["windows"]?.try(&.as_a) || next
          windows.each do |win|
            name = win.dig?("user_vars", PANEL_VAR).try(&.as_s?)
            next unless name
            result[name] = LivePanel.new(os_window_id, win["id"].as_i64, focused)
          end
        end
      end
      result
    end

    def launch_panel(defn : PanelDefinition, hidden : Bool = false) : Int64
      data = launch(defn.cmd,
        type: "os-panel",
        os_panel: defn.to_os_panel_args,
        env: defn.env.map { |k, v| "#{k}=#{v}" } + ["#{PANEL_ENV_VAR}=#{defn.name}"],
        var: ["#{PANEL_VAR}=#{defn.name}"],
        window_title: defn.name,
        os_window_name: "kitty-panels:#{defn.name}",
        os_window_class: defn.app_id,
        keep_focus: defn.mode.dock?)
      id = data.to_i64? || 0_i64
      raise RCError.new("kitty did not return a window id for panel '#{defn.name}'") if id <= 0
      begin
        apply_overrides(RC.panel_match(defn.name), defn.kitty_overrides)
        set_visibility(defn.name, "hide") if hidden
      rescue ex
        close_panel(defn.name) rescue nil
        raise ex
      end
      id
    end

    def apply_overrides(match : String?, overrides : Hash(String, String)) : Nil
      return if overrides.empty?
      colors  = {} of String => Int32?
      spacing = {} of String => Float64?
      image_path    : String? = nil
      image_layout  : String? = nil
      logo_path     : String? = nil
      logo_position : String? = nil
      logo_alpha    : String? = nil
      overrides.each do |key, value|
        kind = begin
          PanelDefinition.override_kind(key)
        rescue ex : ArgumentError
          raise RCError.new(ex.message)
        end
        case kind
        in .opacity?
          opacity = value.to_f64? || raise RCError.new("invalid background_opacity '#{value}', expected a number between 0 and 1")
          set_background_opacity(opacity, match_window: match)
        in .color?
          colors[key] = begin
            Colors.parse(value)
          rescue ex : ArgumentError
            raise RCError.new(ex.message)
          end
        in .padding?
          width = value.to_f64? || raise RCError.new("invalid window_padding_width '#{value}', expected a number")
          %w(left top right bottom).each { |edge| spacing["padding-#{edge}"] = width }
        in .margin?
          width = value.to_f64? || raise RCError.new("invalid window_margin_width '#{value}', expected a number")
          %w(left top right bottom).each { |edge| spacing["margin-#{edge}"] = width }
        in .layouts?
          set_enabled_layouts(value.split(',').map(&.strip), match: match)
        in .ligatures?
          disable_ligatures(value, match_window: match)
        in .background_image? then image_path    = value
        in .image_layout?     then image_layout  = value
        in .window_logo?      then logo_path     = value
        in .logo_position?    then logo_position = value
        in .logo_alpha?       then logo_alpha    = value
        end
      end
      set_colors(colors, match_window: match) unless colors.empty?
      set_spacing(spacing, match_window: match) unless spacing.empty?
      if path = image_path
        set_background_image(data: image_data(path, "background_image"), match: match, layout: image_layout || "configured")
      end
      if path = logo_path
        set_window_logo(data: image_data(path, "window_logo"), position: logo_position || "", alpha: logo_alpha.try(&.to_f64?) || -1.0, match: match)
      end
      nil
    end

    def first_live_panel : LivePanel?
      os_windows = ls.as_a? || return nil
      os_windows.each do |osw|
        focused = osw["is_focused"]?.try(&.as_bool?) || false
        tabs    = osw["tabs"]?.try(&.as_a?) || next
        window  = tabs.compact_map { |tab| tab["windows"]?.try(&.as_a?).try(&.first?) }.first? || next
        return LivePanel.new(osw["id"].as_i64, window["id"].as_i64, focused)
      end
      nil
    end

    def set_visibility(name : String, action : String) : Nil
      resize_os_window(match: RC.panel_match(name), action: action)
    end

    def configure_panel(name : String, os_panel_args : Array(String)) : Nil
      raise RCError.new("nothing to configure") if os_panel_args.empty?
      resize_os_window(match: RC.panel_match(name), action: "os-panel", incremental: true, os_panel: os_panel_args)
    end

    def send_text(name : String, text : String) : Nil
      send_text(match: RC.panel_match(name), data: text)
    end

    def close_panel(name : String) : Nil
      close_window(match: RC.panel_match(name), ignore_no_match: true)
    end

    private def image_data(path : String, key : String) : Bytes | String
      return "-" if path == "none"
      ::File.read(File.expand_path(path)).to_slice
    rescue ex : IO::Error
      raise RCError.new("#{key} '#{path}' cannot be read: #{ex.message}")
    end

    private def envelope(cmd : String, payload : Hash(String, JSON::Any), no_response : Bool = false) : JSON::Any
      message = J.obj({
        "cmd"     => J.s(cmd),
        "version" => J.arr(KITTY_VERSION.to_a.map { |n| J.i(n) }),
        "payload" => J.obj(payload),
      })
      message.as_h["no_response"] = J.b(true) if no_response
      message
    end

    private def roundtrip(message : JSON::Any, timeout : Time::Span, expect_response : Bool = true) : String
      sock = connect
      begin
        sock.read_timeout = timeout
        sock.write(encode(message))
        sock.flush
        sock.close_write
        return "" unless expect_response
        sock.gets_to_end
      rescue ex : IO::TimeoutError
        raise RCError.new("timed out waiting for kitty's response (socket: #{@socket_path})")
      ensure
        sock.close rescue nil
      end
    end

    private def read_frame(sock : UNIXSocket) : String
      io   = IO::Memory.new
      prev = 0_u8
      while byte = sock.read_byte
        io.write_byte(byte)
        break if byte == 0x5C && prev == 0x1B
        prev = byte
      end
      raise RCError.new("kitty closed the connection without a response (socket: #{@socket_path})") if io.bytesize == 0
      io.to_s
    end

    private def encode(message : JSON::Any) : Bytes
      json = message.to_json
      if password = @password
        json = Crypto.encrypt_command(json, password, KITTY_VERSION.to_a.map { |n| JSON::Any.new(n.to_i64) }).to_json
      end
      "\eP@kitty-cmd#{json}\e\\".to_slice
    rescue ex : Crypto::Error
      raise RCError.new(ex.message.to_s)
    end

    private def connect : UNIXSocket
      UNIXSocket.new(@socket_path)
    rescue ex : Socket::ConnectError
      raise RCError.new("cannot connect to kitty at #{@socket_path}: #{ex.message}")
    end

    private def extract_response(raw : String) : JSON::Any
      match = raw.match(RESPONSE_RE) || raise(RCError.new("no response from kitty (is it up? socket: #{@socket_path})"))
      begin
        resp = JSON.parse(match[1])
      rescue ex : JSON::ParseException
        raise RCError.new("malformed response from kitty: #{ex.message}")
      end
      unless resp["ok"]?.try(&.as_bool?)
        error = resp["error"]?.try(&.as_s?) || "unknown kitty remote control error"
        raise RCError.new(error)
      end
      resp
    end
  end
end
