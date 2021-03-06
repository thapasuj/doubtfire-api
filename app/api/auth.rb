require 'grape'
require 'user_serializer'

module Api

  #
  # Provides the authentication API for Doubtfire.
  # Users can sign in via email and password and receive an auth token
  # that can be used with other API calls.
  #
  class Auth < Grape::API
    helpers LogHelper
    
    desc "Sign in"
    params do
      requires :username, type: String, desc: 'User username'
      requires :password, type: String, desc: 'User''s password'
      optional :remember, type: Boolean, desc: 'User has requested to remember login', default: false
    end
    post '/auth' do
      username = params[:username]
      password = params[:password]
      remember = params[:remember]
      
      logger.info "Authenticate #{username} from #{request.ip}"

      if (username =~ /^[Ss]\d{6,10}([Xx]|\d)$/) == 0
        username[0] = ""
      end

      if username.nil? || password.nil?
        error!({"error" => "The request must contain the user username and password."}, 400)
        return
      end
      
      #TODO - usernames case sensitive
      # user = User.find_by_username(username.downcase)
      username = username.downcase

      user = User.find_or_create_by(username: username) {|user|
          user.first_name         = "First Name"
          user.last_name          = "Surname"
          user.email              = username + "@swin.edu.au"
          user.nickname           = "Nickname"
          user.role_id            = Role.student.id
        }

      # Allow acain_student or acain_tutor
      if (username =~ /^acain_.*$/) == 0
        user.username = "acain"
      end

      # Try to authenticate
      if not user.authenticate?(password)
        error!({"error" => "Invalid email or password."}, 401)
      else
        # Restore username if acain_...
        if (username =~ /^acain_.*$/) == 0
          user.username = username
        end

        # Create user if they are a new record
        if user.new_record?
          user.password = "password"
          user.encrypted_password = BCrypt::Password.create("password")
          if not user.valid?
            error!({"error" => "There was an error creating your account in Doubtfire. Please get in contact with your unit convenor or the Doubtfire administrators."})
          end
          user.save
        end

        # if the token has expired
        if user.auth_token_expiry.nil? || user.auth_token_expiry <= DateTime.now
          # create a new token
          user.generate_authentication_token! remember
        else
          # extend the existing token's time
          user.extend_authentication_token remember
        end

        # return the user details
        { user: UserSerializer.new(user), auth_token: user.auth_token }
      end
    end

    desc "Allow tokens to be updated"
    params do
      requires :username, type: String, desc: 'User username'
      optional :remember, type: Boolean, desc: 'User has requested to remember login', default: false
    end
    put '/auth/:auth_token' do
      if params[:auth_token].nil?
        error!({"error" => "Invalid token."}, 404)
      end
      
      logger.info "Update token #{params[:username]} from #{request.ip}"
      
      user = User.find_by_auth_token(params[:auth_token])
      remember = params[:remember]
      
      if user.nil? || user.username != params[:username]
        # logger.info("Token not found.")
        error!({"error" => "Invalid token."}, 404)
      else
        if user.auth_token_expiry > DateTime.now && user.auth_token_expiry < DateTime.now + 1.hour
          user.reset_authentication_token!
          user.generate_authentication_token! remember
        end
        { auth_token: user.auth_token }
      end
    end

    desc "Sign out"
    delete '/auth/:auth_token' do
      user = User.find_by_auth_token(params[:auth_token])
      
      if user
        logger.info "Sign out #{user.username} from #{request.ip}"
        user.reset_authentication_token!
      end
      
      nil
    end
  end
end
