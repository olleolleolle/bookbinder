class ServerDirector
  include BookbinderLogger

  def initialize(directory: nil, port: 41722)
    @directory = directory
    @port = port
  end

  def use_server
    Dir.chdir(@directory) do
      POpen4::popen4("puma -p #{@port}") do |stdout, stderr, stdin, pid|
        begin
          wait_for_server(stdout)
          consume_stream_in_separate_thread(stdout)
          consume_stream_in_separate_thread(stderr)
          yield @port
        ensure
          stop_server(pid)
        end
      end
    end
  end

  private

  def wait_for_server(io)
    begin
      line = io.gets
      raise 'Puma could not start' if line.nil?

      log "Vienna says, #{line}"
    end until line.include?('Listening on')

    log 'Vienna is lovely this time of year.'
  end

  def stop_server(pid)
    Process.kill 'KILL', pid
  end

  # avoids deadlocks by ensuring rack doesn't hang waiting to write to stderr
  def consume_stream_in_separate_thread(stream)
    Thread.new do
      s = nil
      while stream.read(1024, s)
      end
    end
  end
end