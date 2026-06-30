# Capture cursor pagination warnings with backtraces for debugging
# This is temporary - remove after troubleshooting

module CursorPaginationWarningCapture
  @@warnings = []

  def self.warnings
    @@warnings
  end

  def self.clear
    @@warnings = []
  end

  # Monkey-patch ActiveRecord to capture warnings with backtraces
  def self.setup
    original_warn = Warning.method(:warn)

    Warning.define_singleton_method(:warn) do |message|
      if message.include?("Scoped order is ignored")
        backtrace = caller[0..15]
        warning_info = {
          message: message,
          timestamp: Time.current,
          backtrace: backtrace
        }
        @@warnings << warning_info
        puts "\n" + "="*80
        puts "CURSOR PAGINATION WARNING ##{@@warnings.length}"
        puts "="*80
        puts message
        puts "\nBacktrace:"
        backtrace.each { |line| puts "  #{line}" }
        puts "="*80 + "\n"
      end
      original_warn.call(message)
    end
  end
end

# Enable if CURSOR_WARNING_CAPTURE env var is set
if ENV["CURSOR_WARNING_CAPTURE"].present?
  CursorPaginationWarningCapture.setup
end
