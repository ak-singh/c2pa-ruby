# frozen_string_literal: true

# The C library holds raw function pointer addresses for stream callbacks.
# Ruby's GC does not know about those references — if a callback object is
# collected, the next C call into it is a segfault with no Ruby backtrace.
#
# with_gc_stress forces a GC cycle after every allocation, so any unpinned
# callback (a local variable instead of an instance variable) is collected
# immediately and surfaces the crash in the test that caused it.
#
# GC.compact in after(:each) moves objects in memory between tests, catching
# cases where a dangling C pointer to a Ruby object survived from a prior test.
# It does not catch within-test bugs — that is what with_gc_stress is for.

module GcHelpers
  def with_gc_stress
    GC.stress = true
    yield
  ensure
    GC.stress = false
  end
end

RSpec.configure do |config|
  config.include GcHelpers
  config.after { GC.compact if GC.respond_to?(:compact) }
end
