# spec/spec_helper.cr
require "spec"
require "file_utils"
require "../src/kitty_panels"
require "./support/fake_kitty"

ROOT = File.expand_path("..", __DIR__)

def eventually(timeout : Time::Span = 10.seconds, interval : Time::Span = 50.milliseconds, file = __FILE__, line = __LINE__, &)
  deadline = Time.instant + timeout
  loop do
    result = begin
      yield
    rescue KeyError
      nil
    end
    return result if result
    ::fail("condition not met within #{timeout.total_seconds}s", file, line) if Time.instant > deadline
    sleep interval
  end
end
