require "rubygems"
require "sinatra"
require "oauth"
require "oauth/consumer"
require 'grackle'
require 'haml'
require 'json'
require 'uri'

enable :sessions

before do
  session[:oauth] ||= {}  

  @consumer_key = "h8A12ACDWihW9LQZUaTYQ"
  @consumer_secret = "TePhToUj0LNIJ2aBfU2MAz4IZG8LLZvWAqpaj7h4Mhc"

  @host = request.host
  @host << ":4567" if request.host == "localhost"
  
  @consumer ||= OAuth::Consumer.new(@consumer_key, @consumer_secret, :site => "http://twitter.com")
  
  if !session[:oauth][:request_token].nil? && !session[:oauth][:request_token_secret].nil?
    @request_token = OAuth::RequestToken.new(@consumer, session[:oauth][:request_token], session[:oauth][:request_token_secret])
  end
  
  if !session[:oauth][:access_token].nil? && !session[:oauth][:access_token_secret].nil?
    @access_token = OAuth::AccessToken.new(@consumer, session[:oauth][:access_token], session[:oauth][:access_token_secret])
  end
  
  if @access_token
    @client = Grackle::Client.new(:auth => {
      :type => :oauth,
      :consumer_key => @consumer_key,
      :consumer_secret => @consumer_secret,
      :token => @access_token.token, 
      :token_secret => @access_token.secret
    })    
  end
end

get "/" do
  redirect "/edition/"
end

get "/edition/" do
  begin
    @access_token = OAuth::AccessToken.new(@consumer, params[:access_token], params[:access_token_secret])
    @client = Grackle::Client.new(:auth => {
      :type => :oauth,
      :consumer_key => @consumer_key,
      :consumer_secret => @consumer_secret,
      :token => @access_token.token, 
      :token_secret => @access_token.secret
    })
    @n = params[:n].to_i
    if (@n != 5)
      @n = 3
    end
    statuses = @client.statuses.home_timeline? :include_entities => true, :count => 800
    maxsize = statuses.length
    if (@n > maxsize)
      @n = maxsize
    end
    @topstatus = Array.new
    topTweet = Struct.new(:tweet, :rank)
    @topstatus[0] = topTweet.new(statuses[-1], -1.0)
    for status in statuses
      i = 0
      for tweet in @topstatus
        count = (status.retweet_count.to_f**2) / (10*status.user.followers_count.to_f**0.8)
        if(tweet.rank <= count)
          @topstatus.insert(i, topTweet.new(status, count))
          break
        end
        i += 1 
      end
    end
    @last = statuses[-1].created_at
    etag Digest::MD5.hexdigest("#{statuses[0].text}")
    haml :index
  rescue
    etag Digest::MD5.hexdigest("FAILURE!")
    status 203
    halt haml(:fourhundred)
  end
end

post "/validate_config/" do
  begin
    conf = JSON.parse(params[:config])
  rescue
    halt 400
  end
  content_type :json
  n = conf['n']
  if(n == '3' || n == '5')
    status 200
    { :valid => true}.to_json
  else 
    status 401
    { :valid => false, :errors => "Incorrect tweetage amount."}.to_json
  end
end

get "/configure/" do
  session[:ret_url] = params[:return_url]
  session[:fail_url] = params[:failure_url]
  @request_token = @consumer.get_request_token(:oauth_callback => "http://#{@host}/auth")
  session[:oauth][:request_token] = @request_token.token
  session[:oauth][:request_token_secret] = @request_token.secret
  redirect @request_token.authorize_url
end

get "/sample/" do
  send_file File.join(settings.public_folder, 'sample.html')
end

get "/auth" do
  if(params[:denied])
    redirect session[:fail_url]
  end
  @access_token = @request_token.get_access_token :oauth_verifier => params[:oauth_verifier]
  session[:oauth][:access_token] = @access_token.token
  session[:oauth][:access_token_secret] = @access_token.secret
  uri = URI(session[:ret_url])
  if(uri.host == "remote.bergcloud.com")
    redirect "#{session[:ret_url]}?config[access_token]=#{@access_token.token}&config[access_token_secret]=#{@access_token.secret}"
  end
end

get "/logout" do
  session[:oauth] = {}
  redirect "/edition/"
end

error 400 do
  haml :fourhundred
end
