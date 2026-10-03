# spec/unit/config_spec.cr
require "../spec_helper"

private def parse(yaml : String) : Array(KittyPanels::PanelDefinition)
  file = File.tempfile("panels", ".yaml") { |io| io << yaml }
  begin
    KittyPanels.load_definitions(file.path)
  ensure
    file.delete
  end
end

describe KittyPanels do
  describe ".load_definitions" do
    it "parses the shipped example" do
      panels = KittyPanels.load_definitions(File.join(ROOT, "examples", "panels.yaml"))
      panels.map(&.name).should eq(["dropdown", "statusbar"])
      dropdown, statusbar = panels
      dropdown.hide_on_focus_loss.should be_true
      dropdown.kitty_overrides.should eq({"background_opacity" => "0.85"})
      dropdown.cmd.should eq(["/bin/bash", "-l"])
      dropdown.lines.should eq("40")
      statusbar.mode.should eq(KittyPanels::Mode::Dock)
      statusbar.focus_policy.should eq(KittyPanels::FocusPolicy::NotAllowed)
      statusbar.exclusive_zone.should eq(-1)
    end

    it "treats an empty file as no panels" do
      parse("  \n").should be_empty
    end

    it "names the file and the panel when a definition is invalid" do
      error = expect_raises(ArgumentError) do
        parse("panels:\n  broken:\n    edge: sideways\n    cmd: [sh]\n")
      end
      error.message.to_s.should contain("panel 'broken'")
      error.message.to_s.should contain("invalid edge")
    end

    it "reports where an unknown choice sits in the file" do
      error = expect_raises(ArgumentError) do
        parse("panels:\n  fine:\n    cmd: [sh]\n  broken:\n    cmd: [sh]\n    focus_policy: sometimes\n")
      end
      error.message.to_s.should contain("panel 'broken': invalid focus_policy 'sometimes'")
      error.message.to_s.should contain("line 6")
    end

    it "accepts a file without panels" do
      parse("panels:\n").should be_empty
      parse("other: 1\n").should be_empty
    end

    it "rejects a file that is not a mapping of panels" do
      expect_raises(ArgumentError, /expected a mapping/) { parse("- a\n- b\n") }
      expect_raises(ArgumentError, /must map panel names/) { parse("panels: [a, b]\n") }
    end

    it "rejects a panel without a command" do
      expect_raises(ArgumentError, /no command/) { parse("panels:\n  idle:\n    edge: top\n") }
    end

    it "rejects an unusable background opacity" do
      yaml = "panels:\n  glass:\n    kitty_overrides:\n      background_opacity: \"abc\"\n    cmd: [sh]\n"
      expect_raises(ArgumentError, /panel 'glass': invalid background_opacity/) { parse(yaml) }
    end

    it "rejects kitty options that cannot be applied per panel" do
      yaml = "panels:\n  big:\n    kitty_overrides:\n      font_size: \"20\"\n    cmd: [sh]\n"
      expect_raises(ArgumentError, /panel 'big': kitty_override 'font_size' cannot be applied per panel/) { parse(yaml) }
    end

    it "reports YAML syntax errors as argument errors" do
      expect_raises(ArgumentError) { parse("panels:\n  x: [unclosed\n") }
    end
  end
end
