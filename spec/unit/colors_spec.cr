# spec/unit/colors_spec.cr
require "../spec_helper"

describe KittyPanels::Colors do
  it "parses #rrggbb and #rgb hex colors" do
    KittyPanels::Colors.parse("#ff0080").should eq(0xFF0080)
    KittyPanels::Colors.parse("#F0F8FF").should eq(0xF0F8FF)
    KittyPanels::Colors.parse("#f08").should eq(0xFF0088)
    KittyPanels::Colors.parse(" #123456 ").should eq(0x123456)
  end

  it "parses X11 color names, ignoring case and spaces" do
    KittyPanels::Colors.parse("red").should eq(0xFF0000)
    KittyPanels::Colors.parse("AliceBlue").should eq(0xF0F8FF)
    KittyPanels::Colors.parse("light goldenrod yellow").should eq(0xFAFAD2)
    KittyPanels::Colors.parse("rebeccapurple").should eq(0x663399)
  end

  it "parses none and blank as a reset to the configured color" do
    KittyPanels::Colors.parse("none").should be_nil
    KittyPanels::Colors.parse("NONE").should be_nil
    KittyPanels::Colors.parse("   ").should be_nil
  end

  it "rejects colors it cannot parse" do
    expect_raises(ArgumentError, /invalid color 'octarine'/) { KittyPanels::Colors.parse("octarine") }
    expect_raises(ArgumentError, /invalid color '#12'/) { KittyPanels::Colors.parse("#12") }
    expect_raises(ArgumentError, /invalid color '#1234'/) { KittyPanels::Colors.parse("#1234") }
    expect_raises(ArgumentError, /invalid color '#gggggg'/) { KittyPanels::Colors.parse("#gggggg") }
  end
end
