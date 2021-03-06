require 'puppet/network/http'
require 'puppet/util/pidlock'

class Puppet::Network::Server
  attr_reader :server_type, :address, :port

  # Put the daemon into the background.
  def daemonize
    if pid = fork
      Process.detach(pid)
      exit(0)
    end

    # Get rid of console logging
    Puppet::Util::Log.close(:console)

    Process.setsid
    Dir.chdir("/")
    begin
      $stdin.reopen "/dev/null"
      $stdout.reopen "/dev/null", "a"
      $stderr.reopen $stdout
      Puppet::Util::Log.reopen
    rescue => detail
      Puppet::Util.replace_file("/tmp/daemonout", 0644) { |f|
        f.puts "Could not start #{Puppet[:name]}: #{detail}"
      }
      raise "Could not start #{Puppet[:name]}: #{detail}"
    end
  end

  # Create a pidfile for our daemon, so we can be stopped and others
  # don't try to start.
  def create_pidfile
    Puppet::Util.synchronize_on(Puppet[:name],Sync::EX) do
      raise "Could not create PID file: #{pidfile}" unless Puppet::Util::Pidlock.new(pidfile).lock
    end
  end

  # Remove the pid file for our daemon.
  def remove_pidfile
    Puppet::Util.synchronize_on(Puppet[:name],Sync::EX) do
      Puppet::Util::Pidlock.new(pidfile).unlock
    end
  end

  # Provide the path to our pidfile.
  def pidfile
    Puppet[:pidfile]
  end

  def initialize(args = {})
    valid_args = [:handlers, :port]
    bad_args = args.keys.find_all { |p| ! valid_args.include?(p) }.collect { |p| p.to_s }.join(",")
    raise ArgumentError, "Invalid argument(s) #{bad_args}" unless bad_args == ""
    @server_type = Puppet[:servertype] or raise "No servertype configuration found."  # e.g.,  WEBrick, Mongrel, etc.
    http_server_class || raise(ArgumentError, "Could not determine HTTP Server class for server type [#{@server_type}]")

    @port = args[:port] || Puppet[:masterport] || raise(ArgumentError, "Must specify :port or configure Puppet :masterport")
    @address = determine_bind_address

    @listening = false
    @routes = {}
    self.register(args[:handlers]) if args[:handlers]

    # Make sure we have all of the directories we need to function.
    Puppet.settings.use(:main, :ssl, Puppet[:name])
  end

  # Register handlers for REST networking, based on the Indirector.
  def register(*indirections)
    raise ArgumentError, "Indirection names are required." if indirections.empty?
    indirections.flatten.each do |name|
      Puppet::Indirector::Indirection.model(name) || raise(ArgumentError, "Cannot locate indirection '#{name}'.")
      @routes[name.to_sym] = true
    end
  end

  # Unregister Indirector handlers.
  def unregister(*indirections)
    raise "Cannot unregister indirections while server is listening." if listening?
    indirections = @routes.keys if indirections.empty?

    indirections.flatten.each do |i|
      raise(ArgumentError, "Indirection [#{i}] is unknown.") unless @routes[i.to_sym]
    end

    indirections.flatten.each do |i|
      @routes.delete(i.to_sym)
    end
  end

  def listening?
    @listening
  end

  def listen
    raise "Cannot listen -- already listening." if listening?
    @listening = true
    http_server.listen(:address => address, :port => port, :handlers => @routes.keys)
  end

  def unlisten
    raise "Cannot unlisten -- not currently listening." unless listening?
    http_server.unlisten
    @listening = false
  end

  def http_server_class
    http_server_class_by_type(@server_type)
  end

  def start
    create_pidfile
    listen
  end

  def stop
    unlisten
    remove_pidfile
  end

  private

  def http_server
    @http_server ||= http_server_class.new
  end

  def http_server_class_by_type(kind)
    Puppet::Network::HTTP.server_class_by_type(kind)
  end

  def determine_bind_address
    tmp = Puppet[:bindaddress]
    return tmp if tmp != ""
    server_type.to_s == "webrick" ? "0.0.0.0" : "127.0.0.1"
  end
end
