# spec/support/fake_kitty.cr
require "socket"
require "json"

class FakeKitty
  class Window
    property id       : Int64
    property name     : String
    property args     : Array(String)
    property env      : Array(String)
    property os_panel : Array(String)
    property visible  : Bool          = true
    property focused  : Bool          = false
    property opacity  : Float64       = 1.0
    property text     : String        = ""
    property signals  : Array(String) = [] of String

    def initialize(@id : Int64, @name : String, @args : Array(String) = [] of String, @env : Array(String) = [] of String, @os_panel : Array(String) = [] of String)
    end

    def hide_on_focus_loss? : Bool
      @os_panel.includes?("hide-on-focus-loss")
    end
  end

  record Call, cmd : String, payload : Hash(String, JSON::Any), no_response : Bool do
    def string(key : String) : String?
      payload[key]?.try(&.as_s?)
    end

    def strings(key : String) : Array(String)
      payload[key]?.try(&.as_a?).try(&.map(&.as_s)) || [] of String
    end
  end

  NO_MATCH = "No matching windows for expression: %s"

  getter path                    : String
  getter calls                   : Array(Call)          = [] of Call
  getter windows                 : Hash(String, Window) = {} of String => Window
  property stalled               : Bool                 = false
  property exit_with_last_window : Bool                 = false
  @server                        : UNIXServer?
  @failures                      : Hash(String, String) = {} of String => String
  @next_id                       : Int64                = 0_i64

  def initialize(@path : String)
  end

  def start : self
    Dir.mkdir_p(File.dirname(@path))
    File.delete(@path) if File.exists?(@path)
    server  = UNIXServer.new(@path)
    @server = server
    spawn { accept_loop(server) }
    self
  end

  def stop : Nil
    @server.try(&.close) rescue nil
    @server = nil
    File.delete(@path) if File.exists?(@path)
  end

  def crash : Nil
    @windows.clear
    stop
  end

  def running? : Bool
    !@server.nil?
  end

  def fail(cmd : String, message : String) : Nil
    @failures[cmd] = message
  end

  def focus(name : String) : Nil
    @windows.each_value { |window| window.focused = false }
    window = @windows[name]
    window.focused = true if window.visible
  end

  def blur(name : String) : Nil
    window = @windows[name]
    return unless window.focused
    window.focused = false
    window.visible = false if window.hide_on_focus_loss?
  end

  def exit_command(name : String) : Nil
    @windows.delete(name)
  end

  def adopt(name : String) : Window
    @windows[name] = Window.new(next_id, name)
  end

  def calls_for(cmd : String) : Array(Call)
    @calls.select { |call| call.cmd == cmd }
  end

  def last(cmd : String) : Call
    calls_for(cmd).last? || raise "fake kitty never received '#{cmd}'"
  end

  def launches(name : String) : Int32
    calls_for("launch").count { |call| call.strings("var").includes?("kitty_panels_name=#{name}") }
  end

  private def next_id : Int64
    @next_id += 1
  end

  private def accept_loop(server : UNIXServer) : Nil
    while conn = server.accept?
      spawn handle(conn)
    end
  rescue IO::Error
  end

  private def handle(conn : UNIXSocket) : Nil
    while frame = read_frame(conn)
      message = JSON.parse(frame).as_h
      cmd     = message["cmd"].as_s
      payload = message["payload"]?.try(&.as_h?) || {} of String => JSON::Any
      silent  = message["no_response"]?.try(&.as_bool?) || false
      call    = Call.new(cmd, payload, silent)
      @calls << call
      return if @stalled
      reply = begin
        if error = @failures.delete(cmd)
          raise error
        end
        {"ok" => JSON::Any.new(true), "data" => execute(call)}
      rescue ex
        {"ok" => JSON::Any.new(false), "error" => JSON::Any.new(ex.message.to_s)}
      end
      next if silent
      conn << "\eP@kitty-cmd" << reply.to_json << "\e\\"
      conn.flush
    end
  rescue IO::Error | JSON::ParseException
  ensure
    conn.close rescue nil
  end

  private def read_frame(conn : UNIXSocket) : String?
    io   = IO::Memory.new
    prev = 0_u8
    while byte = conn.read_byte
      io.write_byte(byte)
      break if byte == 0x5C && prev == 0x1B
      prev = byte
    end
    raw = io.to_s
    return nil unless raw.starts_with?("\eP@kitty-cmd") && raw.ends_with?("\e\\")
    raw[12..-3]
  end

  private def matched(call : Call) : Window?
    expression = call.string("match") || call.string("match_window")
    unless expression
      return @windows.values.first? if @windows.size == 1
      return nil
    end
    window = @windows[expression.partition("kitty_panels_name=")[2]]?
    return window if window
    return nil if call.payload["ignore_no_match"]?.try(&.as_bool?)
    raise NO_MATCH % expression
  end

  private def execute(call : Call) : JSON::Any
    case call.cmd
    when "ls"
      JSON::Any.new(listing.to_json)
    when "launch"
      name   = call.strings("var").first.partition('=')[2]
      window = Window.new(next_id, name, call.strings("args"), call.strings("env"), call.strings("os_panel"))
      @windows[name] = window
      JSON::Any.new(window.id.to_s)
    when "close-window"
      matched(call).try { |window| @windows.delete(window.name) }
      stop if @exit_with_last_window && @windows.empty? && running?
      JSON::Any.new(nil)
    when "resize-os-window"
      matched(call).try { |window| resize(window, call) }
      JSON::Any.new(nil)
    when "send-text"
      matched(call).try { |window| window.text += call.string("data").to_s.lchop("text:") }
      JSON::Any.new(nil)
    when "get-text"
      JSON::Any.new(matched(call).try(&.text) || "")
    when "signal-child"
      matched(call).try(&.signals.concat(call.strings("signals")))
      JSON::Any.new(nil)
    when "focus-window"
      matched(call).try { |window| focus(window.name) }
      JSON::Any.new(nil)
    when "set-background-opacity"
      matched(call).try { |window| window.opacity = call.payload["opacity"].as_f }
      JSON::Any.new(nil)
    else
      JSON::Any.new(nil)
    end
  end

  private def resize(window : Window, call : Call) : Nil
    case call.string("action")
    when "show"              then window.visible = true
    when "hide"              then window.visible = false
    when "toggle-visibility" then window.visible = !window.visible
    when "os-panel"          then window.os_panel.concat(call.strings("os_panel"))
    end
    window.focused = false unless window.visible
  end

  private def listing
    @windows.values.map do |window|
      {
        id:                 window.id,
        is_focused:         window.focused,
        background_opacity: window.opacity,
        tabs:               [{windows: [{id: window.id, user_vars: {kitty_panels_name: window.name}}]}],
      }
    end
  end
end
