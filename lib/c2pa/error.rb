# frozen_string_literal: true

module C2pa
  # Base error class for all C2PA errors.
  #
  # The C library surfaces errors via a thread-local error slot. After any C
  # call that returns null or a negative value, call {C2pa::API.last_error}
  # to retrieve the message.
  class Error < StandardError; end

  # Raised when the native library cannot be found or fails to load.
  class LibraryNotFoundError < Error; end
end
