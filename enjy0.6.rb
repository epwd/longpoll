# encoding: UTF-8

require 'socket'
require 'json'

if ARGV[1]
    host, port = ARGV
else
    host, port = '127.0.0.1', '2111'
end

$console_log = false

class Enjy
  def initialize(host,port)
    @host = host
    @port = port
  end
  
  def init_server
    @connections_array    = []
    @connection           = TCPServer.open(@host,@port)
    @connections_array[0] = @connection
    
    @i = 0

    @users_sockets = Hash.new {|h,k| h[k]=[]}
    @guids_sockets = Hash.new {|h,k| h[k]=[]}

    @minds_guids = Hash.new {|h,k| h[k]=[]}

    @guid_eq_mind = {}

    @max_connection_one_user = 3

    @test_sockets = Array.new()
  end
  
  def init_onliner
    @thread = Thread.new do
      loop do
        @mind_client_id = Hash.new {|h,k| h[k]=[]}
        sleep 300
      end
    end
  end

  def start
    @for = ''
    loop do
      init_onliner
      init_server
      loop do
        reads,writes = select(@connections_array,nil,nil)
        unless reads.nil?
          reads.each do |client|
          begin
            if client == @connection then
              accept_new
            elsif client.eof?
              terminate(client)
            else
              # second pass
              str = client.gets()
              str = str.force_encoding("UTF-8")
              datasend(str,client)
            end
          rescue => ex
            # error switch connection
          end
          end
        end
        @i += 1
      end
    end
  end

  def accept_new
    @connections_array << @connection.accept_nonblock
  end
  def terminate(client)
    # finish client connection
    client.close
    @connections_array.delete client
  end

  def datasend(str,client)
    begin
      data = JSON.parse(str.chomp!)
    rescue => ex
      # error parsing client data
      return
    end

    # data received
    mindid    = data['mindid']
    client_id = data['client_id']

    if data['action'] == 'whois'
      guid = data['guid']
      
      @test_sockets << client

      @users_sockets[client_id] << client
      @guids_sockets[guid] << client
      @minds_guids[mindid] << guid unless @minds_guids[mindid].include? guid

      @guid_eq_mind[guid] = { :mindid => mindid, :client_id => client_id }

      # show active users of the dialog
      @mind_client_id[mindid] << client_id unless @mind_client_id[mindid].include? client_id
    elsif data['action'] == 'vkauth'
      send_to( @guids_sockets, data['destination'], str, client_id )
    elsif data['action'] == 'lp_send' then

      destination = data['destination']

      @minds_guids[mindid].each do |tmp_guid|
        send_to( @guids_sockets, tmp_guid, str, client_id ) if @guid_eq_mind[tmp_guid][:mindid] == mindid unless @guid_eq_mind[tmp_guid][:client_id] == client_id unless mindid == 'all'
      end

      # send to the host by destination
      send_to( @users_sockets, destination, str, client_id )
    elsif data['action'] == 'online'

      data = { :action => 'online', :message => {
        :action => 'online',
        :mindid => mindid,
        :users  => @mind_client_id[mindid]
      }}
      # online clients
      client.puts data.to_json.to_s
    end
  end
  
  def send_to( sockets, destination, str, client_id )
    return if destination == client_id
    sockets[destination].each do |socket|
      begin
        socket.puts str
      rescue => ex
        # error send data
      end
    end
    # delete the used guid
    sockets.delete destination
  end

end

Enjy.new(host,port).start
