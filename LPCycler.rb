# encoding: UTF-8

require 'socket'

class Messages
    attr_reader :error_connection
    attr_reader :error_parse_receive_message
    attr_reader :error_get_online
    attr_reader :warning_no_received_message
    attr_reader :warning_no_full_received_message
    
    # Static messages
    def initialize
        @error_connection                 = "LP: ОШИБКА соединения"
        @error_parse_receive_message      = "LP-Thread: ОШИБКА парсинга полученных данных от Enjy"
        @error_get_online                 = "LP-Online: ОШИБКА получения данных от Enjy"
        
        @waring_get_online                = "LP-Online: ПРЕДУПРЕЖДЕНИЕ неудачная попытка получения данных"
        @warning_no_received_message      = 'LP: ПРЕДУПРЕЖДЕНИЕ Данные от Enjy получены но нет сообщения'
        @warning_no_full_received_message = 'LP: ПРЕДУПРЕЖДЕНИЕ Нет данных от Enjy'
    end
    
    # Dynamic messages for listen
    def all_listen_noauth(guid)
        '{"action":"whois","client_id":"noauth","destination":"enjy","guid":"'+guid+'"}'
    end
    def all_listen_auth(client_id,guid)
        '{"action":"whois","client_id":"'+client_id+'","destination":"enjy","guid":"'+guid+'"}'
    end
    def mind_listen_auth(mindid,client_id,guid)
        '{"mindid":"'+mindid+'","action":"whois","client_id":"'+client_id+'","destination":"enjy","guid":"'+guid+'"}'
    end
    
    # Dynamic messages for send
    def send(mindid,action,client_id,destination,guid,msg)
        '{"mindid":"'+mindid+'","action":"'+action+'","client_id":"'+client_id+'","destination":"'+destination+'","guid":"'+guid+'","message":'+msg.to_json+'}'
    end
    
    # Dynamic messages get online
    def online(mindid)
        '{"mindid":"'+mindid+'","action":"online"}'
    end
end

class Success
    attr_accessor :error_message
    attr_accessor :full_received_message
    attr_accessor :received_message_online

    attr_reader :received_message
    attr_reader :action_pool
    attr_reader :action_message

    def initialize(messages)
        @messages = messages
        
        #default
        @received_message = nil
        @received_message_online = nil
        @full_received_message = nil

        @action_pool = nil
        @action_message = nil
    end

    def create
        if @received_message_online
            @action_pool      = @received_message_online['action']
            @action_message   = @action_pool
        end
        return (@error_message = @messages.warning_no_full_received_message) if @full_received_message.nil?
        if @full_received_message.has_key?('message') then
            @action_pool      = @full_received_message['action'] if @full_received_message.has_key?('action')
            @received_message = @full_received_message['message']
            @action_message   = @full_received_message['message']['action'] if @full_received_message['message'].has_key?('action')
            @received_message['m_online'] = @received_message_online['users'] if @received_message_online
        end
    end
end

class Control
    attr_accessor :mindid
    attr_accessor :action
    attr_accessor :client_id
    attr_accessor :destination
    attr_accessor :msg

    def initialize( client_id, client_data, client_noauth_bool,messages )
        @messages = messages
        
        @client_noauth_bool = client_noauth_bool
        @client_id   = client_id
        @client_data = client_data
        
        @guid = 'none_guid'

        # Default data
        init_data_default_for_send
    end

    def who_listen
        case action_listen
        when 'all_listen_noauth'
            @messages.all_listen_noauth( @client_data['guid'] )
        when 'all_listen_auth'
            @messages.all_listen_auth( client_id, @client_data['guid'] )
        when 'mind_listen_auth'
            @messages.mind_listen_auth( @client_data['mind'], client_id, @client_data['guid'] )
        end
    end
    def what_send
        @messages.send(@mindid,@action,@client_id,@destination,@guid,@msg)
    end
    def online
        @messages.online(@mindid)
    end

private
    def action_listen
        return 'all_listen_noauth' if @client_noauth_bool
        return 'mind_listen_auth'  if @client_data.has_key?('mind') unless @client_noauth_bool
        return 'all_listen_auth'
    end
    def init_data_default_for_send
        @mindid      = @client_data.has_key?('mind') ? @client_data['mind'] : 'all' unless @client_data.nil?
        @action      = 'lp_send'
        @client_id   = 'none_client_id' if @client_id.nil?
        @destination = 'none_destination'
        @guid        = @client_data['guid'] if @client_data.has_key?('guid') unless @client_data.nil?
        @msg         = {:action=>'nodata'}
    end
end

class LPCycler
    attr_accessor :control

    attr_reader :success
    attr_accessor :connection

    def initialize( client_id, client_data, client_noauth_bool )
        @seconds = 20

        @messages = Messages.new()    # Add text to obj   
        @success  = Success.new(@messages)
        @control  = Control.new(client_id,client_data,client_noauth_bool,@messages)

    end

    def connect
        begin
            @connection  = TCPSocket.open($host_pool,$port_pool)
            true
        rescue => ex
            @success.error_message = "#{@messages.error_connection} - #{ex}"
            false
        end
    end
    def send
        return unless connect
        @connection.puts @control.what_send
        @connection.close
    end
    def listen
        return unless connect
        @connection.puts @control.who_listen

        time_   = @seconds*10
        current_listen = listen_thread

        # Завершаем задержку завершения "циклера" если сообщение поступило раньше time
        (time_).times do
            @stop ? break : sleep(0.1)
        end
        
        current_listen.terminate
        online_inner
        # Подготовим ответ
        @success.create
        @connection.close
    end
    def online_inner
        return if @control.mindid == 'all'
        @connection.puts @control.online
        loop do
            begin
                str = @connection.gets.chomp
                unless str.nil?
                    full_received_message_online = JSON.parse(str)
                    @success.received_message_online = full_received_message_online['message']
                    return true if full_received_message_online['action'] == 'online'
                end
            rescue => ex
                break
                # Вообще нужен некий сборщик ошибок
            end
        end
        false
    end
    # Завернуть в поток
    def online
        return false unless connect
        @connection.puts @control.online

        begin
            @connection.set_encoding('UTF-8')
            str = @connection.gets.chomp
            if str.nil? then
                @success.error_message = @messages.waring_get_online
            else
                @success.full_received_message = JSON.parse(str)
                @success.create
                return true
            end
        rescue => ex
            @success.error_message = "#{@messages.error_get_online} - #{ex}"
        end
        return false
    end

private
    def listen_thread
        Thread.abort_on_exception = true
        @thread = Thread.new do
            loop do
                sleep 0.1
                str = nil
                begin
                    @connection.set_encoding('UTF-8')
                    str = @connection.gets.chomp
                    if str.nil? then
                        next
                    else
                        @success.full_received_message = JSON.parse(str)
                    end
                rescue => ex
                    @success.error_message = "#{@messages.error_parse_receive_message} - #{ex}"
                    next
                end
                @stop = true
            end
        end      
    end

    def enjy_down(ex='no error')
        [200, {'Content-Type' => 'text/plain'},[ '{"action":"nodata","info":"enjy from lp: reset connection by peer => "'+ex.to_s+'}' ]]
    end 
end