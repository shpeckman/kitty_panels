# src/kitty_panels/engine.cr
require "./timing"
require "./rc"

class KittyPanels::Engine
  GRACE = Timing::ENGINE_GRACE

  getter process : Process? = nil
  @exited        : Channel(Nil)

  def initialize(@socket_path : String, @kitty : String = "kitty", @config_path : String? = nil, @log_path : String? = nil)
    exited = Channel(Nil).new
    exited.close
    @exited = exited
  end

  def start : Nil
    Dir.mkdir_p(File.dirname(@socket_path))
    write_config
    ::File.delete(@socket_path) if ::File.exists?(@socket_path)
    args = [
      "--config", config_path,
      "--class", "kitty-panels",
      "--name", "kitty-panels",
      "--listen-on", "unix:#{@socket_path}",
      "--start-as", "hidden",
      "-o", "allow_remote_control=socket-only",
      "-o", "confirm_os_window_close=0",
    ]
    process = ::File.open(log_path, "a") do |log|
      Process.new(@kitty, args: args, output: log, error: log)
    end
    exited   = Channel(Nil).new
    @process = process
    @exited  = exited
    spawn do
      process.wait rescue nil
      exited.close
    end
  end

  def exited? : Bool
    @exited.closed?
  end

  def wait_exit : Nil
    @exited.receive?
  end

  def terminate(grace : Time::Span = GRACE) : Nil
    process  = @process || return
    @process = nil
    return if exited?
    process.signal(Signal::TERM) rescue nil
    select
    when @exited.receive?
    when timeout(grace)
      process.signal(Signal::KILL) rescue nil
      @exited.receive?
    end
  end

  def wait_ready(timeout : Time::Span = 15.seconds) : Nil
    rc       = RC.new(@socket_path)
    deadline = Time.instant + timeout
    until rc.alive?
      if @process && exited?
        raise "kitty engine exited during startup, see #{log_path}#{log_tail()}"
      end
      raise "kitty engine did not become ready within #{timeout.total_seconds.to_i}s, see #{log_path}#{log_tail()}" if Time.instant > deadline
      sleep 100.milliseconds
    end
  end

  private def config_path : String
    @config_path || "#{@socket_path}.conf"
  end

  private def log_path : String
    @log_path || "#{@socket_path}.log"
  end

  private def log_tail(lines : Int32 = 20) : String
    return "" unless ::File.exists?(log_path)
    all = ::File.read_lines(log_path).reject(&.empty?)
    return "" if all.empty?
    "\n--- engine log tail ---\n#{all.last(lines).join('\n')}"
  rescue
    ""
  end

  private def write_config : Nil
    ::File.write(config_path, <<-CONF)
    allow_remote_control socket-only
    confirm_os_window_close 0
    dynamic_background_opacity yes
    CONF
  end
end
