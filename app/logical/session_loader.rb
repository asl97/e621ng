class SessionLoader
  class AuthenticationFailure < Exception ; end

  attr_reader :session, :cookies, :request, :params

  def initialize(request)
    @request = request
    @session = request.session
    @cookies = request.cookie_jar
    @params = request.parameters
    @remember_validator = ActiveSupport::MessageVerifier.new(Danbooru.config.remember_key, serializer: JSON, digest: "SHA256")
  end

  def load
    CurrentUser.user = User.anonymous
    CurrentUser.ip_addr = request.remote_ip

    if has_api_authentication?
      load_session_for_api
    elsif session[:user_id]
      load_session_user
    elsif has_remember_token?
      load_remember_token
    end

    CurrentUser.user.unban! if CurrentUser.user.ban_expired? && !Danbooru.config.readonly_mode
    if CurrentUser.user.is_blocked?
      recent_ban = CurrentUser.user.recent_ban
      ban_message = "Account is banned: forever"
      if recent_ban && recent_ban.expires_at.present?
        ban_message = "Account is suspended for another #{recent_ban.expire_days}"
      end
      raise AuthenticationFailure.new(ban_message)
    end
    set_statement_timeout
    update_last_logged_in_at unless Danbooru.config.readonly_mode
    update_last_ip_addr unless Danbooru.config.readonly_mode
    set_time_zone
    set_safe_mode
    refresh_old_remember_token
    DanbooruLogger.initialize(request, session, CurrentUser.user)
  end

  def has_api_authentication?
    request.authorization.present? || params[:login].present? || params[:api_key].present?
  end

  def has_remember_token?
    cookies.encrypted[:remember].present?
  end

private

  def set_statement_timeout
    timeout = CurrentUser.user.statement_timeout
    ActiveRecord::Base.connection.execute("set statement_timeout = #{timeout}")
  end

  def load_remember_token
    begin
      message = @remember_validator.verify(cookies.encrypted[:remember], purpose: "rbr")
      return if message.nil?
      user = User.find_by_id(message.to_i)
      return unless user
      CurrentUser.user = user
      session[:user_id] = user.id
    rescue
      return
    end
  end

  def refresh_old_remember_token
    if cookies.encrypted[:remember]
      cookies.encrypted[:remember] = {value: @remember_validator.generate(CurrentUser.id, purpose: "rbr", expires_in: 14.days), expires: Time.now + 14.days, httponly: true, same_site: :lax, secure: Rails.env.production?}
    end
  end

  def load_session_for_api
    if request.authorization
      authenticate_basic_auth
    elsif params[:login].present? && params[:api_key].present?
      authenticate_api_key(params[:login], params[:api_key])
    else
      raise AuthenticationFailure
    end
  end

  def authenticate_basic_auth
    credentials = ::Base64.decode64(request.authorization.split(' ', 2).last || '')
    login, api_key = credentials.split(/:/, 2)
    authenticate_api_key(login, api_key)
  end

  def authenticate_api_key(name, api_key)
    CurrentUser.user = User.authenticate_api_key(name, api_key)

    if CurrentUser.user.nil?
      raise AuthenticationFailure.new
    end
  end

  def load_session_user
    user = User.find_by_id(session[:user_id])
    CurrentUser.user = user if user
  end

  def update_last_logged_in_at
    return if CurrentUser.is_anonymous?
    return if CurrentUser.last_logged_in_at && CurrentUser.last_logged_in_at > 1.week.ago
    CurrentUser.user.update_attribute(:last_logged_in_at, Time.now)
  end

  def update_last_ip_addr
    return if CurrentUser.is_anonymous?
    return if CurrentUser.user.last_ip_addr == @request.remote_ip
    CurrentUser.user.update_attribute(:last_ip_addr, @request.remote_ip)
  end

  def set_time_zone
    Time.zone = CurrentUser.user.time_zone
  end

  def set_safe_mode
    safe_mode = Danbooru.config.safe_mode || params[:safe_mode].to_s.truthy? || CurrentUser.user.enable_safe_mode?
    CurrentUser.safe_mode = safe_mode
  end
end
