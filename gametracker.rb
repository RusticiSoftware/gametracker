#!/usr/bin/ruby

require 'lib/elo'

require 'rubygems'
require 'bundler/setup'


require 'sinatra'
require 'sequel'
require 'pg'
require 'activesupport'
require 'haml'
require 'sass'
require 'bcrypt'
require 'rack-flash'
require 'sinatra/redirect_with_flash'
require 'json'

require 'uri'

require 'net/https'
require 'net/http'

use Rack::Session::Cookie
use Rack::Flash

db = Sequel.connect('sqlite://my.db')

before do
  @players = Player.order(:name).map(:name)
  #@current_user = current_user
  #unless request.path_info == '/log_in'
  #  session[:flash] = nil 
  #end
  #require_auth = ['/new_game', '/new_user', '/update_password', '/new_doubles_game']
  #if require_auth.index(request.path_info) && !@current_user
  #  not_logged_in("Please log in")
  #end
end

helpers do

  def link_to_player player, current=nil
    if player.capitalize == current
      "#{player}"
    else
      "<a href=\"/user/#{Player.id_from_name(player.capitalize)}\">#{player}</a>"
    end
  end

end

class DoublesTeam < Sequel::Model(db[:doubles_teams])
  def self.id_from_players(p1, p2)
    query = filter(:player1 => p1).and(:player2 => p2)
    if query.empty?
      return nil
    else
      return query.first[:id]
    end
  end
end

class DoublesGame < Sequel::Model(db[:doubles_games])
end

class DoublesSet < Sequel::Model(db[:doubles_sets])
  one_to_many :doublegames
end

class Game < Sequel::Model
  many_to_one :winner, :class => :Player
  many_to_one :loser, :class => :Player
  many_to_one :gameset

  def self.for_user_id(user_id)
    filter(:winner_id => user_id).or(:loser_id => user_id).order(:created_at.desc)
  end
end

class Player < Sequel::Model
  one_to_many :winner_games, :class => :Game, :key => :winner_id
  one_to_many :loser_games, :class => :Game, :key => :loser_id

  def self.id_from_name(name)
    filter(:name => name).first[:id] || nil
  end

  def self.name_from_id(id)
    filter(:id => id).first[:name] || nil
  end

  def self.update_password(user, password)
    password_salt = BCrypt::Engine.generate_salt
    password_hash = BCrypt::Engine.hash_secret(password, password_salt)
    Player.filter(:id => user.id).update(:password_hash => password_hash, :password_salt => password_salt)
  end

  def self.new_player(name, email, department, password)
    Player.create(
        :name => name.capitalize,
        :email => email,
        :department => department.capitalize,
        :sets_elo => 1000,
        :games_elo => 1000,
        :created_at => Time.now())
  end

end

class GameSet < Sequel::Model(db[:sets])
  one_to_many :games
end

class GameTracker < Sinatra::Application

  def compute_doubles_rankings
    teams = DoublesTeam.all
    ranked = []
    teams.each do |t|
      ranked.push({:p1 => Player.name_from_id(t[:player1]), :p2 => Player.name_from_id(t[:player2]), :sets_elo => t[:sets_elo]})
    end

    ranked = ranked.sort_by { |k| k[:sets_elo] }.reverse
    return ranked
  end

  def compute_rankings
    players = Player.all
    ranked = []
    unranked = []
    players.each do |p|
      wins = GameSet.filter(:winner_id => p[:id]).count || 0
      loses = GameSet.filter(:loser_id => p[:id]).count || 0
      if wins == 0 && loses == 0
        percentage = 0
      else
        percentage = (wins/(wins+loses).to_f).round(3) * 100
      end
      if (wins + loses) > 2
        ranked.push({:name => p[:name], :wins => wins, :loses => loses, :percentage => percentage, :department => p[:department], :sets_elo => p[:sets_elo], :games_elo => p[:games_elo]})
      else
        unranked.push({:name => p[:name], :wins => wins, :loses => loses, :percentage => percentage, :department => p[:department], :sets_elo => p[:sets_elo], :games_elo => p[:games_elo]})
      end
    end

    ranked = ranked.sort_by { |k| k[:sets_elo] }.reverse
    return ranked, unranked
  end

  def set_winner(winners)
    winners.group_by do |e|
      e
    end.values.max_by(&:size).first
  end

  def save_game(winner, loser, served, score, set)
    points = score.split('-')
    elo = calc_games_elo(winner, loser);
    game = Game.create(
        :winner_id => Player.id_from_name(winner),
        :loser_id => Player.id_from_name(loser),
        :served => Player.id_from_name(served),
        :winner_score => points[0],
        :loser_score => points[1],
        :set_id => set,
        :created_at => Time.now(),
        :winner_elo => elo[:winner],
        :loser_elo => elo[:loser]
    )
  end

  def save_doubles_game(winner1, winner2, loser1, loser2, winner_team, loser_team, served, score, set)
    points = score.split('-')
    doublesgame = DoublesGame.create(
        :winner1_id => winner1,
        :winner2_id => winner2,
        :loser1_id => loser1,
        :loser2_id => loser2,
        :winner_team_id => winner_team,
        :loser_team_id => loser_team,
        :served_id => Player.id_from_name(served),
        :winner_score => points[0],
        :loser_score => points[1],
        :set_id => set,
        :created_at => Time.now()
    )
  end

  def calc_doubles_sets_elo(w, l)
    w_cur_elo = DoublesTeam.filter(:id => w).first[:sets_elo] || 0
    puts "w_cur_elo #{w_cur_elo}"
    l_cur_elo = DoublesTeam.filter(:id => l).first[:sets_elo] || 0
    puts "l_cur_elo #{l_cur_elo}"
    w_elo = Elo.compute(w_cur_elo, [[l_cur_elo, 1]])
    puts "w_elo #{w_elo}"
    l_elo = Elo.compute(l_cur_elo, [[w_cur_elo, 0]])
    puts "l_elo #{l_elo}"
    DoublesTeam.filter(:id => w).update(:sets_elo => w_elo)
    DoublesTeam.filter(:id => l).update(:sets_elo => l_elo)
    {:winner => w_elo, :loser => l_elo}
  end

  def calc_sets_elo(w, l)
    w_cur_elo = Player.filter(:id => w).first[:sets_elo] || 0
    l_cur_elo = Player.filter(:id => l).first[:sets_elo] || 0
    w_elo = Elo.compute(w_cur_elo, [[l_cur_elo, 1]])
    l_elo = Elo.compute(l_cur_elo, [[w_cur_elo, 0]])
    Player.filter(:id => w).update(:sets_elo => w_elo)
    Player.filter(:id => l).update(:sets_elo => l_elo)
    {:winner => w_elo, :loser => l_elo}
  end

  def send_statement(w, l)
    w_email = Player.filter(:id => w).first[:email] || "blank@example.com"
    l_email = Player.filter(:id => l).first[:email] || "blank@example.com"
    l_name = Player.filter(:id => l).first[:name]
    w_name = Player.name_from_id(w)

    @host = 'cloud.scorm.com'
    @port = '80'
    @user = 'TestUser'
    @pass = 'password'
    @post_ws = "/ScormEngineInterface/TCAPI/public/statements"

    @payload ={
        "actor" => {"mbox" => ["mailto:#{w_email}"], "name" => ["#{w_name}"], "objectType" => "Person"},
        "verb" => "experienced",
        "object" => {"definition" => {"name" => {"en-US" => "Beating #{l_name} at Rustici PingPong"}}, "id" => "http://scorm.com/pong/beat#{l_name}", "objectType" => "Activity"}
    }.to_json

    puts @payload

    req = Net::HTTP::Post.new(@post_ws, initheader = {'Content-Type' => 'application/json'})
    req.basic_auth @user, @pass
    req.body = @payload
    response = Net::HTTP.new(@host, @port).start { |http| http.request(req) }
    puts "Response #{response.code} #{response.message}:#{response.body}"


    @user_family = "0YPSZ3S4LA"
    @pass_family = "Wpy1axMyvPmdQbpPB1a4vDdYVLAJ6sdvd8569WAj"
    @post_family = "/ScormEngineInterface/TCAPI/MLEARNCONA/statements"

    req = Net::HTTP::Post.new(@post_family, initheader = {'Content-Type' => 'application/json'})
    req.basic_auth @user_family, @pass_family
    req.body = @payload
    response = Net::HTTP.new(@host, @port).start { |http| http.request(req) }
    puts "Response #{response.code} #{response.message}:#{response.body}"

    @host_watershed = "watershed.ws"
    @user_watershed = "tj.seabrooks+pong@scorm.com"
    @pass_watershed = "scorm2004"
    @post_watershed = "/tc/statements"

    @payload_95 = {
        "actor" => {
            "mbox" => "mailto:#{w_email}",
            "name" => "#{w_name}",
            "objectType" => "Agent"
        },

        "verb" => {
            "id" => "http://tincanapi.com/rustici/verbs/pongwin",
            "display" => {
                "en-US" => "Won Rustici Pong Against"
            }
        },

        "object" => {
            "mbox" => "mailto:#{l_email}",
            "name" => "#{l_name}",
            "objectType" => "Agent"
        }
    }.to_json


    uri = URI.parse("https://watershed.ws")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    req = Net::HTTP::Post.new(@post_watershed, initheader = {'Content-Type' => 'application/json'})
    req.basic_auth @user_watershed, @pass_watershed
    req.body = @payload_95
    response = http.request(req)
    puts "Response #{response.code} #{response.message}:#{response.body}"


  end


  def calc_games_elo(w, l)
    w_id = Player.id_from_name(w)
    l_id = Player.id_from_name(l)
    w_cur_elo = Player.filter(:id => w_id).first[:games_elo] || 0
    l_cur_elo = Player.filter(:id => l_id).first[:games_elo] || 0
    w_elo = Elo.compute(w_cur_elo, [[l_cur_elo, 1]])
    l_elo = Elo.compute(l_cur_elo, [[w_cur_elo, 0]])
    Player.filter(:id => w_id).update(:games_elo => w_elo)
    Player.filter(:id => l_id).update(:games_elo => l_elo)
    {:winner => w_elo, :loser => l_elo}
  end

  def sets_with_games(player=nil)
    sets_with_game_count = []
    if player.nil?
      sets = GameSet.order(:created_at.desc).limit(10)
    else
      sets = GameSet.filter(:winner_id => player).or(:loser_id => player).order(:created_at.desc).limit(10)
    end
    sets.each do |set|
      sets_with_game_count.push({
                                    :winner => Player.name_from_id(set[:winner_id]),
                                    :loser => Player.name_from_id(set[:loser_id]),
                                    :winner_elo => set[:winner_elo],
                                    :loser_elo => set[:loser_elo],
                                    :num_games => Game.filter(:set_id => set[:id].to_s()).count
                                })
    end
    sets_with_game_count
  end

  def doubles_sets_with_games(p1=nil)
    dsets_with_game_count = []
    if p1.nil?
      dsets = DoublesSet.order(:created_at.desc).limit(10)
    else
      dsets_p1 = DoublesSet.filter(:winner1_id => p1).or(:winner2_id => p1).or(:loser1_id => p1).or(:loser2_id => p1)
    end
    dsets.each do |set|
      dsets_with_game_count.push({
                                     :w1 => Player.name_from_id(set[:winner1_id]),
                                     :w2 => Player.name_from_id(set[:winner2_id]),
                                     :l1 => Player.name_from_id(set[:loser1_id]),
                                     :l2 => Player.name_from_id(set[:loser2_id]),
                                     :num_games => DoublesGame.filter(:set_id => set[:id]).count
                                 })
    end
    dsets_with_game_count
  end

  def not_logged_in(message)
    flash[:notice] = message
    redirect '/log_in'
  end

  def current_user
    Player.filter(:id => session[:player].id).first if session[:player]
  end

  def find_previous_elo(player, id)
    previous_game = Game.filter(:winner_id => player).or(:loser_id => player).filter(:id < id).order(:id).last
    if previous_game == nil
      return
    elsif player == previous_game[:winner_id]
      return previous_game[:winner_elo]
    else
      return previous_game[:loser_elo]
    end
  end

  def sm_data(user_id)
    data = []
    opponents = []
    games = Game.filter(:winner_id => user_id).or(:loser_id => user_id).order(:created_at.desc)
    games.reverse.each do |game|
      winner_id = game[:winner_id]
      loser_id = game[:loser_id]
      winner_previous_elo = find_previous_elo(winner_id, game[:id]) || 0
      loser_previous_elo = find_previous_elo(loser_id, game[:id]) || 0

      difference = (winner_previous_elo - loser_previous_elo).abs
      scale = difference == 0 ? 0 : 1 / difference.to_f
      if user_id == game[:loser_id].to_s
        scale = scale * -1
        opponents << Player.name_from_id(game[:winner_id])
      else
        opponents << Player.name_from_id(game[:loser_id])
      end
      data << scale
    end
    {:data => data, :opponents => opponents}
  end

  get '/sm_data' do
    sm_data(params[:user_id]).to_json
  end

  get '/' do
    @games = Game.order(:created_at.desc).limit(10)
    @sets = sets_with_games
    @doubles_sets = doubles_sets_with_games
    @ranked, @unranked = compute_rankings
    @doubles_ranked = compute_doubles_rankings
    haml :gametracker
#    haml :tttpp, :layout => false
  end

  get '/new_doubles_game' do
    haml :new_doubles_game
  end

  get '/new_game' do
    haml :new_game
  end

  get '/user/:id' do
    @user = Player.filter(:id => params[:id]).first
    @games = Game.for_user_id(params[:id])
    @sets = sets_with_games(params[:id])

    haml :user
  end

  post '/new_doubles_game' do
    puts params.inspect
    winners = []
    ["winner1", "winner2", "winner3", "winner4", "winner5"].each do |w|
      if params[w] != ""
        winners << params[w]
      end
    end

    players = [params[:player1], params[:player2], params[:player3], params[:player4]]
    players_ids = []
    players.each do |p|
      players_ids.push(Player.id_from_name(p))
    end
    team1 = players_ids[0..1].sort
    team2 = players_ids[2..3].sort
    team1_id = DoublesTeam.id_from_players(team1[0], team1[1])
    team2_id = DoublesTeam.id_from_players(team2[0], team2[1])
    if (team1_id == nil)
      t1 = DoublesTeam.create(:player1 => team1[0], :player2 => team1[1], :created_at => Time.now(), :sets_elo => 1000)
      team1_id = t1.id
    end
    if (team2_id == nil)
      t2 = DoublesTeam.create(:player1 => team2[0], :player2 => team2[1], :created_at => Time.now(), :sets_elo => 1000)
      team2_id = t2.id
    end

    set_winner = set_winner(winners)
    if (set_winner == "team1")
      set_winner_id = team1_id
      set_loser_id = team2_id
    else
      set_winner_id = team2_id
      set_loser_id = team1_id
    end
    sets_elo = calc_doubles_sets_elo(set_winner_id, set_loser_id)

    if set_winner == 'team1'
      set = DoublesSet.create(:winner1_id => team1[0], :winner2_id => team1[1], :loser1_id => team2[0], :loser2_id => team2[1], :winner_team_id => team1_id, :loser_team_id => team2_id, :created_at => Time.now(), :winner_elo => sets_elo[:winner], :loser_elo => sets_elo[:loser])
    elsif set_winner == 'team2'
      set = DoublesSet.create(:winner1_id => team2[0], :winner2_id => team2[1], :loser1_id => team1[0], :loser2_id => team1[1], :winner_team_id => team2_id, :loser_team_id => team1_id, :created_at => Time.now(), :winner_elo => sets_elo[:winner], :loser_elo => sets_elo[:loser])
    end

    if winners[0] == 'team1'
      save_doubles_game(team1[0], team1[1], team2[0], team2[1], team1_id, team2_id, params[:served1], params[:score1], set[:id]);
    else
      save_doubles_game(team2[0], team2[1], team1[0], team1[1], team2_id, team1_id, params[:served1], params[:score1], set[:id]);
    end
    if winners[1] == 'team1'
      save_doubles_game(team1[0], team1[1], team2[0], team2[1], team1_id, team2_id, params[:served2], params[:score2], set[:id]);
    else
      save_doubles_game(team2[0], team2[1], team1[0], team1[1], team2_id, team1_id, params[:served2], params[:score2], set[:id]);
    end
    if winners[2] == 'team1'
      save_doubles_game(team1[0], team1[1], team2[0], team2[1], team1_id, team2_id, params[:served3], params[:score3], set[:id]);
    else
      save_doubles_game(team2[0], team2[1], team1[0], team1[1], team2_id, team1_id, params[:served3], params[:score3], set[:id]);
    end
    if winners[3] && winners[3] == 'team1'
      save_doubles_game(team1[0], team1[1], team2[0], team2[1], team1_id, team2_id, params[:served4], params[:score4], set[:id]);
    elsif winners[3]
      save_doubles_game(team2[0], team2[1], team1[0], team1[1], team2_id, team1_id, params[:served4], params[:score4], set[:id]);
    end
    if winners[4] && winners[4] == 'team1'
      save_doubles_game(team1[0], team1[1], team2[0], team2[1], team1_id, team2_id, params[:served5], params[:score5], set[:id]);
    elsif winners[4]
      save_doubles_game(team2[0], team2[1], team1[0], team1[1], team2_id, team1_id, params[:served5], params[:score5], set[:id]);
    end

    redirect '/'

  end

  post '/new_game' do
    winners = []
    ["winner1", "winner2", "winner3"].each do |w|
      if params[w] != ""
        winners << params[w]
      end
    end

    players = [params[:player1], params[:player2]]
    player1 = Player.id_from_name(players[0])
    player2 = Player.id_from_name(players[1])

    set_winner = set_winner([params[:winner1], params[:winner2], params[:winner3]])
    set_winner_id = Player.id_from_name(set_winner)
    set_loser_id = Player.id_from_name(players - [set_winner])

    #Rustici Mod - Send TinCanAPI Statement about winner and loser
    send_statement(set_winner_id, set_loser_id)

    sets_elo = calc_sets_elo(set_winner_id, set_loser_id)
    set = GameSet.create(:winner_id => set_winner_id, :loser_id => set_loser_id, :created_at => Time.now(), :winner_elo => sets_elo[:winner], :loser_elo => sets_elo[:loser])

    save_game(winners[0], players - [winners[0]], params[:served1], params[:score1], set[:id])
    save_game(winners[1], players - [winners[1]], params[:served2], params[:score2], set[:id])
    if (winners[2])
      save_game(winners[2], players - [winners[2]], params[:served3], params[:score3], set[:id])
    end
    redirect '/'

  end

  get '/new_user' do
    haml :new_user
  end

  post '/new_user' do
    Player.new_player(params[:name], params[:email], params[:department], params[:password])
    redirect '/'
  end

  get '/elo_ratings' do
    p1_cur_elo = Player.filter(:name => params[:p1]).first[:sets_elo]
    p2_cur_elo = Player.filter(:name => params[:p2]).first[:sets_elo]
    p1_wins = Elo.compute(p1_cur_elo, [[p2_cur_elo, 1]])
    p1_loses = Elo.compute(p1_cur_elo, [[p2_cur_elo, 0]])
    p2_wins = Elo.compute(p2_cur_elo, [[p1_cur_elo, 1]])
    p2_loses = Elo.compute(p2_cur_elo, [[p1_cur_elo, 0]])
    return {:p1_wins => p1_wins, :p1_loses => p1_loses, :p2_wins => p2_wins, :p2_loses => p2_loses, :p1_cur => p1_cur_elo, :p2_cur => p2_cur_elo}.to_json
  end

  get '/log_in' do
    haml :log_in
  end

  post '/log_in' do
    #player = Player.authenticate(params[:email], params[:password])
    #if player
    #  session[:player] = player
    #  flash.now[:notice] = "Signed-in"  
    redirect '/'
    #else
    #  not_logged_in("Invalid email or password")
    #end
  end

  get '/log_out' do
    session[:player] = nil
    redirect '/'
  end

  get '/css/:sheet.css' do |sheet|
    headers 'Content-Type' => 'text/css; charset=utf-8'
    sass :"css/#{sheet}"
  end

  get '/update_password' do
    haml :update_password
  end

  post '/update_password' do
    Player.update_password(@current_user, params[:password])
    redirect '/', flash[:notice] => "Password updated"
  end

  get '/ranks' do
    rankings = compute_doubles_rankings
    rankings.to_json
  end


end
