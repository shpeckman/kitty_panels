# spec/unit/rc_spec.cr
require "../spec_helper"

private def with_kitty(&)
  path  = File.join(File.tempname("kitty-panels-rc"), "kitty.sock")
  kitty = FakeKitty.new(path).start
  begin
    yield KittyPanels::RC.new(path), kitty
  ensure
    kitty.stop
    FileUtils.rm_rf(File.dirname(path))
  end
end

private def definition(name : String) : KittyPanels::PanelDefinition
  KittyPanels::PanelDefinition.new(name).tap do |defn|
    defn.cmd = ["/bin/sh", "-c", "exec cat"]
    defn.env["GREETING"] = "hi"
  end
end

describe KittyPanels::RC do
  it "reports whether kitty answers" do
    with_kitty do |rc, kitty|
      rc.alive?.should be_true
      kitty.stop
      rc.alive?.should be_false
    end
  end

  it "raises a connection error when no kitty is listening" do
    rc = KittyPanels::RC.new("/nonexistent/kitty.sock")
    expect_raises(KittyPanels::RCError, /cannot connect/) { rc.ls }
  end

  it "launches a panel as a tagged os-panel window" do
    with_kitty do |rc, kitty|
      defn = definition("bar")
      defn.mode = KittyPanels::Mode::Dock
      rc.launch_panel(defn).should eq(1)
      call = kitty.last("launch")
      call.string("type").should eq("os-panel")
      call.strings("args").should eq(["/bin/sh", "-c", "exec cat"])
      call.strings("var").should eq(["kitty_panels_name=bar"])
      call.strings("env").should eq(["GREETING=hi", "KITTY_PANELS_PANEL_NAME=bar"])
      call.strings("os_panel").should eq(defn.to_os_panel_args)
      call.string("os_window_class").should eq("kitty-panels")
      call.payload["keep_focus"].as_bool.should be_true
      call.payload.has_key?("cwd").should be_false
    end
  end

  it "applies the background opacity override after launch" do
    with_kitty do |rc, kitty|
      defn = definition("glass")
      defn.kitty_overrides["background_opacity"] = "0.85"
      rc.launch_panel(defn)
      kitty.windows["glass"].opacity.should eq(0.85)
    end
  end

  it "applies color, spacing, layout and ligature overrides after launch" do
    with_kitty do |rc, kitty|
      defn = definition("themed")
      defn.kitty_overrides["background"] = "#112233"
      defn.kitty_overrides["color1"] = "red"
      defn.kitty_overrides["selection_background"] = "none"
      defn.kitty_overrides["window_padding_width"] = "12"
      defn.kitty_overrides["window_margin_width"] = "2.5"
      defn.kitty_overrides["ligatures"] = "never"
      defn.kitty_overrides["enabled_layouts"] = "tall, stack"
      rc.launch_panel(defn)
      colors = kitty.last("set-colors")
      colors.string("match_window").should eq("var:kitty_panels_name=themed")
      colors.payload["colors"]["background"].as_i.should eq(0x112233)
      colors.payload["colors"]["color1"].as_i.should eq(0xFF0000)
      colors.payload["colors"]["selection_background"].raw.should be_nil
      spacing = kitty.last("set-spacing")
      spacing.string("match_window").should eq("var:kitty_panels_name=themed")
      %w(padding-left padding-top padding-right padding-bottom).each do |edge|
        spacing.payload["settings"][edge].as_f.should eq(12.0)
      end
      %w(margin-left margin-top margin-right margin-bottom).each do |edge|
        spacing.payload["settings"][edge].as_f.should eq(2.5)
      end
      ligatures = kitty.last("disable-ligatures")
      ligatures.string("match_window").should eq("var:kitty_panels_name=themed")
      ligatures.string("strategy").should eq("never")
      layouts = kitty.last("set-enabled-layouts")
      layouts.string("match").should eq("var:kitty_panels_name=themed")
      layouts.strings("layouts").should eq(["tall", "stack"])
    end
  end

  it "sends background image and window logo data after launch" do
    image = File.tempfile("kitty-panels-bg", ".png") { |io| io.write(Bytes[1, 2, 3, 4]) }
    logo  = File.tempfile("kitty-panels-logo", ".png") { |io| io.write(Bytes[9, 8, 7]) }
    begin
      with_kitty do |rc, kitty|
        defn = definition("art")
        defn.kitty_overrides["background_image"] = image.path
        defn.kitty_overrides["background_image_layout"] = "tiled"
        defn.kitty_overrides["window_logo"] = logo.path
        defn.kitty_overrides["window_logo_position"] = "center"
        defn.kitty_overrides["window_logo_alpha"] = "0.5"
        rc.launch_panel(defn)
        background = kitty.last("set-background-image")
        background.string("match").should eq("var:kitty_panels_name=art")
        background.string("layout").should eq("tiled")
        background.string("data").should eq(Base64.strict_encode(String.new(Bytes[1, 2, 3, 4])))
        window_logo = kitty.last("set-window-logo")
        window_logo.string("match").should eq("var:kitty_panels_name=art")
        window_logo.string("position").should eq("center")
        window_logo.payload["alpha"].as_f.should eq(0.5)
        window_logo.string("data").should eq(Base64.strict_encode(String.new(Bytes[9, 8, 7])))
      end
    ensure
      image.delete
      logo.delete
    end
  end

  it "removes an image when the override is none" do
    with_kitty do |rc, kitty|
      defn = definition("plain")
      defn.kitty_overrides["background_image"] = "none"
      defn.kitty_overrides["window_logo"] = "none"
      rc.launch_panel(defn)
      kitty.last("set-background-image").string("data").should eq("-")
      kitty.last("set-window-logo").string("data").should eq("-")
    end
  end

  it "closes the window again when an override cannot be applied" do
    with_kitty do |rc, kitty|
      defn = definition("broken")
      defn.kitty_overrides["font_size"] = "20"
      expect_raises(KittyPanels::RCError, /cannot be applied per panel/) { rc.launch_panel(defn) }
      kitty.windows.should be_empty
    end
  end

  it "closes the window again when an override value is unreadable" do
    with_kitty do |rc, kitty|
      defn = definition("broken")
      defn.kitty_overrides["background_image"] = "/nonexistent/bg.png"
      expect_raises(KittyPanels::RCError, /cannot be read/) { rc.launch_panel(defn) }
      kitty.windows.should be_empty
    end
  end

  it "reports the first live window of a dedicated panel" do
    with_kitty do |rc, kitty|
      rc.first_live_panel.should be_nil
      window = kitty.adopt("solo")
      seen   = rc.first_live_panel.not_nil!
      seen.os_window_id.should eq(window.id)
      seen.window_id.should eq(window.id)
      seen.focused.should be_false
      kitty.focus("solo")
      rc.first_live_panel.not_nil!.focused.should be_true
    end
  end

  it "launches a panel hidden" do
    with_kitty do |rc, kitty|
      rc.launch_panel(definition("quiet"), hidden: true)
      kitty.windows["quiet"].visible.should be_false
    end
  end

  it "closes the window again when a step after the launch fails" do
    with_kitty do |rc, kitty|
      kitty.fail("resize-os-window", "compositor said no")
      expect_raises(KittyPanels::RCError, /compositor said no/) { rc.launch_panel(definition("quiet"), hidden: true) }
      kitty.windows.should be_empty
      glass = definition("glass")
      glass.kitty_overrides["background_opacity"] = "0.5"
      kitty.fail("set-background-opacity", "opacity is locked")
      expect_raises(KittyPanels::RCError, /opacity is locked/) { rc.launch_panel(glass) }
      kitty.windows.should be_empty
    end
  end

  it "lists live panels with their ids and focus" do
    with_kitty do |rc, kitty|
      rc.launch_panel(definition("a"))
      rc.launch_panel(definition("b"))
      kitty.focus("b")
      live = rc.live_panels
      live.keys.sort!.should eq(["a", "b"])
      live["a"].focused.should be_false
      live["b"].focused.should be_true
      live["b"].window_id.should eq(2)
    end
  end

  it "surfaces kitty's error message" do
    with_kitty do |rc, _|
      expect_raises(KittyPanels::RCError, /No matching windows/) { rc.set_visibility("ghost", "hide") }
    end
  end

  it "ignores a missing window when closing a panel" do
    with_kitty do |rc, _|
      rc.close_panel("ghost")
    end
  end

  it "sends text without waiting for a response" do
    with_kitty do |rc, kitty|
      rc.launch_panel(definition("term"))
      rc.send_text("term", "ls\n")
      eventually { kitty.windows["term"].text == "ls\n" }
      call = kitty.last("send-text")
      call.no_response.should be_true
      call.string("data").should eq("text:ls\n")
    end
  end

  it "validates arguments before talking to kitty" do
    with_kitty do |rc, kitty|
      expect_raises(KittyPanels::RCError, /invalid extent/) { rc.get_text(extent: "everything") }
      expect_raises(KittyPanels::RCError, /nothing to configure/) { rc.configure_panel("x", [] of String) }
      expect_raises(KittyPanels::RCError, /no signals/) { rc.signal_child([] of String) }
      kitty.calls.should be_empty
    end
  end

  it "upcases signal names" do
    with_kitty do |rc, kitty|
      rc.launch_panel(definition("job"))
      rc.signal_child(["sigusr1"], match: KittyPanels::RC.panel_match("job"))
      kitty.windows["job"].signals.should eq(["SIGUSR1"])
    end
  end

  it "times out when kitty never answers" do
    with_kitty do |rc, kitty|
      kitty.stalled = true
      expect_raises(KittyPanels::RCError, /no response|timed out/) { rc.command("ls", timeout: 200.milliseconds) }
    end
  end
end
