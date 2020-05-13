# encoding: UTF-8

module RouteLongPool
  def self.route(pool)
    data    = Hash.new
    success = pool.success
    mindid  = pool.control.mindid

    case success.action_message
    when nil
      data = { 
        :bool => false,
        :pool => true,
        :code => 800,
        :info => 'No message-action for pool route'
      }
    when 'comment_add', 'mind_add'
      data = {
        :bool   => true,
        :pool   => true,
        :action => success.action_message,
        :code   => 0,
        :notice => success.received_message,
        :user   => NewUser.get_user( nil, success.received_message['u_id'] )
      }
    when 'follow'
      data = {
        :bool   => true,
        :pool   => true,
        :code   => 0,
        :action => success.action_message,
        :follow => success.received_message,
        :user   => NewUser.get_user( nil, success.received_message['inserted'] )
      }
    when 'follow_remove'
      data = {
        :bool   => true,
        :pool   => true,
        :code   => 0,
        :action => success.action_message,
        :follow => success.received_message,
        :user   => NewUser.get_user( nil, success.received_message['key'] )
      }
    when 'mind_plus', 'mind_minus'
      data = {
        :bool   => true,
        :pool   => true,
        :code   => 0,
        :action => 'mind_like',
        :notice => success.received_message,
        :user   => NewUser.get_user( nil, success.received_message['u_like_id'] )
      }
    when 'online'
      data = {
        :bool   => true,
        :pool   => true,
        :code   => 0,
        :action => 'online',
      }
    end
    unless mindid == 'all'
      data[:m_online] = NewUser.get_online( success.received_message_online['users'] )
      data[:m_id] = mindid
    end
    return data
  end
end