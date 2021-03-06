class SessionController < ApplicationController

  skip_before_filter :redirect_to_login_if_required

  def csrf
    render json: {csrf: form_authenticity_token }
  end

  def create
    params.require(:login)
    params.require(:password)

    login = params[:login].strip
    login = login[1..-1] if login[0] == "@"

    if login =~ /@/
      @user = User.where(email: Email.downcase(login)).first
    else
      @user = User.where(username_lower: login.downcase).first
    end

    if @user.present?

      # If the site requires user approval and the user is not approved yet
      if SiteSetting.must_approve_users? && !@user.approved? && !@user.admin?
        render json: {error: I18n.t("login.not_approved")}
        return
      end

      # If their password is correct
      if @user.confirm_password?(params[:password])

        if @user.is_banned?
          render json: { error: I18n.t("login.banned", {date: I18n.l(@user.banned_till, format: :date_only)}) }
          return
        end

        if @user.email_confirmed?
          log_on_user(@user)
          render_serialized(@user, UserSerializer)
          return
        else
          render json: {
            error: I18n.t("login.not_activated"),
            reason: 'not_activated',
            sent_to_email: @user.email_logs.where(email_type: 'signup').order('created_at DESC').first.try(:to_address) || @user.email,
            current_email: @user.email
          }
          return
        end
      end
    end

    render json: {error: I18n.t("login.incorrect_username_email_or_password")}
  end

  def forgot_password
    params.require(:login)

    user = User.where('username_lower = :username or email = :email', username: params[:login].downcase, email: Email.downcase(params[:login])).first
    if user.present?
      email_token = user.email_tokens.create(email: user.email)
      Jobs.enqueue(:user_email, type: :forgot_password, user_id: user.id, email_token: email_token.token)
    end
    # always render of so we don't leak information
    render json: {result: "ok"}
  end

  def destroy
    reset_session
    log_off_user
    render nothing: true
  end

end
